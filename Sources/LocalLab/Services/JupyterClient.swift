import Foundation

/// Local service layer. No listener, cookie import, credential persistence or server-wide mutations.
actor JupyterClient: KernelService, RemoteFileService {
    private var remoteShell: RemoteShellTerminal?
    private let base: URL
    private let origin: String
    private var token = ""
    private var kernel: KernelInfo?
    private var socket: URLSessionWebSocketTask?
    private let session: URLSession
    private let webSocketSession: URLSession
    private var heartbeat: Task<Void, Never>?
    private var socketReader: Task<Void, Never>?
    private var inbox: [Message] = []
    private var waiter: CheckedContinuation<Message, Error>?
    private var socketFailure: Error?
    private var activeRequestID: String?
    private var executing = false
    private let sessionID = UUID().uuidString

    init(base: URL = URL(string: "https://lecture.cs.tum.de:9000/user/go97lep/api")!) {
        self.base = base
        let components = URLComponents(url: base, resolvingAgainstBaseURL: false)!
        self.origin = "\(components.scheme!)://\(components.host!)" + (components.port.map { ":\($0)" } ?? "")
        let configuration = URLSessionConfiguration.ephemeral
        configuration.httpCookieStorage = nil
        configuration.urlCache = nil
        configuration.timeoutIntervalForRequest = 20
        configuration.timeoutIntervalForResource = 40
        session = URLSession(configuration: configuration, delegate: NoRedirect(), delegateQueue: nil)
        let socketConfiguration = URLSessionConfiguration.ephemeral
        socketConfiguration.httpCookieStorage = nil
        socketConfiguration.urlCache = nil
        socketConfiguration.timeoutIntervalForRequest = 20
        // WebSocket lifetime must not inherit the 40-second HTTP resource deadline.
        webSocketSession = URLSession(configuration: socketConfiguration, delegate: NoRedirect(), delegateQueue: nil)
    }
    func shellTerminal() async throws -> RemoteShellTerminal {
        guard !token.isEmpty, kernel != nil else { throw LabError.message("請先連線至伺服器。") }
        if let remoteShell { return remoteShell }
        let terminal = RemoteShellTerminal(base: base, credential: token); remoteShell = terminal; return terminal
    }
    func ownedKernelID() -> String? { kernel?.id }
    func runLiveVerification(root: URL) async -> URL {
        // Credential stays within the app/service process; no credential export.
        await AppLiveVerifier.run(credential: token, root: root)
    }

    private func requestHTTP(_ method: String, _ path: String, body: [String: Any]? = nil, allowed: Set<Int> = [200], query: [URLQueryItem] = []) async throws -> (Int, Data) {
        var components = URLComponents(url: base, resolvingAgainstBaseURL: false)!
        components.path += path
        components.queryItems = query.isEmpty ? nil : query
        var request = URLRequest(url: components.url!)
        request.httpMethod = method
        request.setValue("token " + token, forHTTPHeaderField: "Authorization")
        if let body {
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = try JSONSerialization.data(withJSONObject: body)
        }
        let (data, response) = try await session.data(for: request)
        guard let response = response as? HTTPURLResponse else { throw LabError.message("未收到 HTTP 回應。") }
        guard allowed.contains(response.statusCode) else { throw LabError.http(response.statusCode) }
        return (response.statusCode, data)
    }
    private func http(_ method: String, _ path: String, body: [String: Any]? = nil, allowed: Set<Int> = [200], query: [URLQueryItem] = []) async throws -> Data {
        try await requestHTTP(method, path, body: body, allowed: allowed, query: query).1
    }

    func connect(token newToken: String) async throws -> ConnectionInfo {
        guard !executing else { throw LabError.message("請先中斷正在執行的程式。") }
        token = newToken.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !token.isEmpty else { throw LabError.message("請輸入 API token。") }
        // If cleanup failed previously, the replacement credential can clean up the same owned kernel.
        if kernel != nil { try await disconnectKeepingToken() }
        let existing = try JSONDecoder().decode([KernelInfo].self, from: await http("GET", "/kernels"))
        let data = try await http("GET", "/kernelspecs")
        guard let specs = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let list = specs["kernelspecs"] as? [String: [String: Any]],
              let entry = list.sorted(by: { $0.key < $1.key }).first(where: { ($0.value["spec"] as? [String: Any])?["language"] as? String == "python" }) else {
            token = ""; throw LabError.message("伺服器沒有提供 Python 核心。")
        }
        let createdData = try await http("POST", "/kernels", body: ["name": entry.key], allowed: [201])
        let created = try JSONDecoder().decode(KernelInfo.self, from: createdData)
        guard !existing.contains(where: { $0.id == created.id }) else { throw LabError.message("伺服器未傳回新的專用核心；已停止操作以保護既有核心。") }
        kernel = created
        do {
            var components = URLComponents(url: base, resolvingAgainstBaseURL: false)!
            components.scheme = base.scheme == "https" ? "wss" : "ws"
            components.path += "/kernels/\(created.id)/channels"
            components.queryItems = [URLQueryItem(name: "session_id", value: sessionID)]
            var request = URLRequest(url: components.url!)
            request.setValue("token " + token, forHTTPHeaderField: "Authorization")
            request.setValue(origin, forHTTPHeaderField: "Origin")
            let ws = webSocketSession.webSocketTask(with: request)
            ws.maximumMessageSize = 8 * 1024 * 1024
            socket = ws; ws.resume(); startReader(ws)
            let id = try await send("kernel_info_request", content: [:])
            let pythonVersion = try await withThrowingTaskGroup(of: String.self) { group in
                group.addTask { [self] in
                    while true {
                        let message = try await self.nextMessage()
                        if message.parentID == id && message.kind == "kernel_info_reply" {
                            return ((message.content["language_info"] as? [String: Any])?["version"] as? String ?? "").components(separatedBy: " ")[0]
                        }
                    }
                }
                group.addTask {
                    try await Task.sleep(nanoseconds: 15_000_000_000)
                    ws.cancel(with: .goingAway, reason: nil)
                    throw LabError.message("WebSocket 連線逾時。請確認 VPN 與遠端服務。")
                }
                let value = try await group.next() ?? ""; group.cancelAll(); return value
            }
            startHeartbeat(ws)
            let displayName = (entry.value["spec"] as? [String: Any])?["display_name"] as? String ?? "Python"
            return ConnectionInfo(kernel: created, existingCount: existing.count, displayName: displayName, pythonVersion: pythonVersion)
        } catch {
            do { try await disconnectKeepingToken() }
            catch { throw LabError.message("連線失敗，專用核心 \(created.id) 的清理尚未確認。請重新連線以重試清理。") }
            throw error
        }
    }

    private func ping(_ ws: URLSessionWebSocketTask) async throws {
        let completion = OneShotContinuation<Void>()
        let deadline = Task {
            do { try await Task.sleep(nanoseconds: 8_000_000_000) }
            catch { return }
            if completion.resolve(.failure(LabError.message("WebSocket 存活檢查逾時。"))) {
                ws.cancel(with: .goingAway, reason: nil)
            }
        }
        defer { deadline.cancel() }
        try await withTaskCancellationHandler {
            try Task.checkCancellation()
            try await withCheckedThrowingContinuation { continuation in
                completion.install(continuation)
                ws.sendPing { error in
                    if let error { completion.resolve(.failure(error)) }
                    else { completion.resolve(.success(())) }
                }
            }
        } onCancel: { completion.resolve(.failure(CancellationError())) }
    }
    private func startReader(_ ws: URLSessionWebSocketTask) {
        socketReader?.cancel(); inbox = []; socketFailure = nil
        socketReader = Task { [weak self] in
            do {
                while !Task.isCancelled {
                    guard let self else { return }
                    let message = try await self.receive(ws)
                    await self.enqueue(message, socket: ws)
                }
            } catch { await self?.readerFailed(error, socket: ws) }
        }
    }
    private func enqueue(_ message: Message, socket ws: URLSessionWebSocketTask) {
        guard socket === ws, message.parentID == activeRequestID else { return }
        if let pending = waiter { waiter = nil; pending.resume(returning: message) }
        else {
            if inbox.count >= 1000 { inbox.removeFirst() }
            inbox.append(message)
        }
    }
    private func readerFailed(_ error: Error, socket ws: URLSessionWebSocketTask) {
        guard socket === ws else { return }
        socketFailure = error
        if let pending = waiter { waiter = nil; pending.resume(throwing: error) }
    }
    private func nextMessage() async throws -> Message {
        if !inbox.isEmpty { return inbox.removeFirst() }
        if let failure = socketFailure { throw failure }
        return try await withCheckedThrowingContinuation { waiter = $0 }
    }
    private func startHeartbeat(_ ws: URLSessionWebSocketTask) {
        heartbeat?.cancel()
        heartbeat = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 20_000_000_000)
                guard !Task.isCancelled, let self else { return }
                do { try await self.ping(ws) }
                catch { return }
            }
        }
    }
    private func send(_ type: String, content: [String: Any]) async throws -> String {
        guard let ws = socket else { throw LabError.message("請先連線到遠端核心。") }
        let id = UUID().uuidString
        activeRequestID = id; inbox = []
        let message: [String: Any] = ["header": ["msg_id": id, "username": "local-lab", "session": sessionID, "date": ISO8601DateFormatter().string(from: Date()), "msg_type": type, "version": "5.3"], "parent_header": [:], "metadata": [:], "content": content, "channel": "shell", "buffers": []]
        let data = try JSONSerialization.data(withJSONObject: message)
        try await ws.send(.string(String(decoding: data, as: UTF8.self)))
        return id
    }
    private struct Message { let kind: String; let parentID: String; let content: [String: Any] }
    private func receive(_ ws: URLSessionWebSocketTask) async throws -> Message {
        let message = try await ws.receive()
        let data: Data
        switch message {
        case .string(let text): data = Data(text.utf8)
        case .data: throw LabError.message("遠端回傳了未支援的二進位訊息格式。")
        @unknown default: throw LabError.message("未支援的 WebSocket 訊息。")
        }
        guard let object = try JSONSerialization.jsonObject(with: data) as? [String: Any] else { throw LabError.message("無法解析核心回應。") }
        return Message(kind: (object["header"] as? [String: Any])?["msg_type"] as? String ?? "", parentID: (object["parent_header"] as? [String: Any])?["msg_id"] as? String ?? "", content: object["content"] as? [String: Any] ?? [:])
    }

    func execute(code: String, onEvent: @escaping @Sendable (KernelEvent) async -> Void) async throws {
        guard !executing, let ws = socket, kernel != nil else { throw LabError.message("核心未連線或仍在執行。") }
        executing = true; defer { executing = false; activeRequestID = nil; inbox = [] }
        // Check the channel before dispatch; never replay an ambiguously sent program.
        do { try await ping(ws) }
        catch { throw LabError.message("核心連線已中斷；本次程式尚未送出。請重新連線後執行。") }
        let id = try await send("execute_request", content: ["code": code, "silent": false, "store_history": true, "user_expressions": [:], "allow_stdin": false, "stop_on_error": true])
        var reply: Bool?; var idle = false; var clearPending = false
        while reply == nil || !idle {
            try Task.checkCancellation()
            let message = try await nextMessage()
            guard message.parentID == id else { continue }
            let c = message.content
            if clearPending && ["stream", "error", "display_data", "execute_result"].contains(message.kind) { await onEvent(.clear); clearPending = false }
            switch message.kind {
            case "stream": await onEvent(.text(c["text"] as? String ?? "", isError: c["name"] as? String == "stderr"))
            case "error":
                let traceback = (c["traceback"] as? [String])?.joined(separator: "\n") ?? "\(c["ename"] ?? "Error"): \(c["evalue"] ?? "")"
                await onEvent(.text(traceback.replacingOccurrences(of: "\u{001B}\\[[0-9;]*m", with: "", options: .regularExpression) + "\n", isError: true))
            case "execute_result", "display_data":
                let data = c["data"] as? [String: Any] ?? [:]
                if let encoded = data["image/png"] as? String, let image = Data(base64Encoded: encoded, options: .ignoreUnknownCharacters) { await onEvent(.image(image)) }
                else if let text = data["text/plain"] as? String { await onEvent(.text(text + "\n", isError: false)) }
            case "clear_output":
                if c["wait"] as? Bool == true { clearPending = true } else { await onEvent(.clear) }
            case "execute_reply": reply = c["status"] as? String == "ok"
            case "status": if c["execution_state"] as? String == "idle" { idle = true }
            default: break
            }
        }
        await onEvent(.completed(success: reply == true))
    }
    func remoteDirectory(_ path: String) async throws -> [RemoteEntry] {
        let path = try RemotePath.validated(path)
        let data = try await http("GET", "/contents/" + path)
        guard let object = try JSONSerialization.jsonObject(with: data) as? [String: Any], object["type"] as? String == "directory", let items = object["content"] as? [[String: Any]] else {
            throw LabError.message("遠端路徑不是資料夾。")
        }
        return try JSONDecoder().decode([RemoteEntry].self, from: JSONSerialization.data(withJSONObject: items)).sorted {
            if ($0.type == "directory") != ($1.type == "directory") { return $0.type == "directory" }
            return $0.name.localizedStandardCompare($1.name) == .orderedAscending
        }
    }
    func remoteFile(_ path: String) async throws -> RemoteTextFile {
        let path = try RemotePath.validated(path)
        let (metadataStatus, metadata) = try await requestHTTP("GET", "/contents/" + path, allowed: [200, 404], query: [URLQueryItem(name: "content", value: "0")])
        guard metadataStatus != 404 else { throw RemoteFileMissing(path: path) }
        let entry = try JSONDecoder().decode(RemoteEntry.self, from: metadata)
        guard ["file", "notebook"].contains(entry.type) else { throw LabError.message("此檔案請在 JupyterLab 開啟；App 編輯器目前支援文字檔。") }
        let limit = entry.type == "notebook" ? 8_388_608 : 1_048_576
        guard (entry.size ?? 0) <= limit else { throw LabError.message("此檔案超過 App 預覽大小限制。") }
        let (contentStatus, data) = try await requestHTTP("GET", "/contents/" + path, allowed: [200, 404], query: entry.type == "notebook" ? [] : [URLQueryItem(name: "format", value: "text")])
        guard contentStatus != 404 else { throw RemoteFileMissing(path: path) }
        guard data.count <= limit + 65_536, let object = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw LabError.message("遠端檔案格式不正確或超過預覽限制。")
        }
        let content: String?
        if entry.type == "notebook", let notebook = object["content"] as? [String: Any] {
            content = String(decoding: try JSONSerialization.data(withJSONObject: notebook, options: [.sortedKeys]), as: UTF8.self)
        } else { content = object["content"] as? String }
        guard let text = content, text.utf8.count <= limit else {
            throw LabError.message("此檔案無法作為 UTF-8 文字開啟。")
        }
        let model = try JSONDecoder().decode(RemoteEntry.self, from: data)
        return RemoteTextFile(entry: model, content: text)
    }
    func saveRemoteFile(path: String, content: String, expectedContent: String) async throws -> RemoteTextFile {
        let current = try await remoteFile(path)
        guard current.entry.writable else { throw LabError.message("此遠端檔案沒有寫入權限。") }
        guard current.content == expectedContent else { throw RemoteConflict(file: current) }
        let body: [String: Any]
        if current.entry.type == "notebook" {
            let notebook = try NotebookDocument(content)
            body = ["type": "notebook", "format": "json", "content": notebook.root]
        } else { body = ["type": "file", "format": "text", "content": content] }
        _ = try await http("PUT", "/contents/" + RemotePath.validated(path), body: body, allowed: [200, 201])
        let saved = try await remoteFile(path)
        let matches = current.entry.type == "notebook" ? try NotebookDocument(content).matchesSaved(saved.content) : saved.content == content
        guard matches else { throw RemoteConflict(file: saved) }
        return saved
    }
    func createRemoteFile(path: String, content: String) async throws -> RemoteTextFile {
        let path = try RemotePath.validated(path)
        let (status, _) = try await requestHTTP("GET", "/contents/" + path, allowed: [200, 404], query: [URLQueryItem(name: "content", value: "0")])
        guard status == 404 else { throw LabError.message("同名遠端檔案已存在，請使用另一個名稱。") }
        let notebook = path.lowercased().hasSuffix(".ipynb") ? try NotebookDocument(content.isEmpty ? NotebookDocument.empty : content) : nil
        let body: [String: Any] = notebook.map { ["type": "notebook", "format": "json", "content": $0.root] } ?? ["type": "file", "format": "text", "content": content]
        _ = try await http("PUT", "/contents/" + path, body: body, allowed: [200, 201])
        let saved = try await remoteFile(path)
        let matches = try notebook?.matchesSaved(saved.content) ?? (saved.content == content)
        guard matches else { throw RemoteConflict(file: saved) }
        return saved
    }
    func createRemoteDirectory(path: String) async throws {
        let path = try RemotePath.validated(path)
        let (status, _) = try await requestHTTP("GET", "/contents/" + path, allowed: [200, 404], query: [URLQueryItem(name: "content", value: "0")])
        guard status == 404 else { throw LabError.message("同名遠端項目已存在。") }
        _ = try await http("PUT", "/contents/" + path, body: ["type": "directory"], allowed: [200, 201])
    }
    func interrupt() async throws {
        guard let kernel else { throw LabError.message("沒有可中斷的專用核心。") }
        _ = try await http("POST", "/kernels/\(kernel.id)/interrupt", allowed: [204])
    }
    private func disconnectKeepingToken() async throws {
        try await remoteShell?.stop(); remoteShell = nil
        heartbeat?.cancel(); heartbeat = nil
        socketReader?.cancel(); socketReader = nil
        if let pending = waiter { waiter = nil; pending.resume(throwing: CancellationError()) }
        inbox = []; activeRequestID = nil
        socket?.cancel(with: .normalClosure, reason: nil); socket = nil
        if let owned = kernel {
            _ = try await http("DELETE", "/kernels/\(owned.id)", allowed: [204, 404])
            _ = try await http("GET", "/kernels/\(owned.id)", allowed: [404])
            kernel = nil
        }
    }
    func disconnect() async throws {
        try await disconnectKeepingToken()
        token = ""
    }
}

final class NoRedirect: NSObject, URLSessionTaskDelegate {
    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse, newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void) { completionHandler(nil) }
}

/// Serializes timeout, cancellation, and repeated framework callbacks.
/// Resolution before installation is retained; a continuation is resumed once.
final class OneShotContinuation<Value>: @unchecked Sendable {
    private let lock = NSLock()
    private var continuation: CheckedContinuation<Value, Error>?
    private var result: Result<Value, Error>?
    private var installed = false
    func install(_ value: CheckedContinuation<Value, Error>) {
        lock.lock()
        precondition(!installed)
        installed = true
        let completed = result
        if completed == nil { continuation = value }
        lock.unlock()
        if let completed { value.resume(with: completed) }
    }
    @discardableResult func resolve(_ value: Result<Value, Error>) -> Bool {
        lock.lock()
        guard result == nil else { lock.unlock(); return false }
        result = value
        let pending = continuation; continuation = nil
        lock.unlock()
        pending?.resume(with: value)
        return true
    }
}
