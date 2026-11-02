import Foundation
import Darwin

protocol ShellTerminal: Sendable {
    func start(onText: @escaping @Sendable (String) async -> Void) async throws
    func send(_ text: String) async throws
    func stop() async throws
}
actor LocalShellTerminal: ShellTerminal {
    private let pythonVersion: String?
    init(pythonVersion: String? = nil) { self.pythonVersion = pythonVersion }
    private var process: Process?
    private var input: Pipe?
    private var output: Pipe?
    func start(onText: @escaping @Sendable (String) async -> Void) throws {
        guard process == nil else { return }
        let value = Process(), incoming = Pipe(), outgoing = Pipe()
        let bundled = Bundle.main.bundleURL.appendingPathComponent("Contents/MacOS/LocalLabShellBridge")
        let testBridge = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent(".build/LocalLabShellBridge")
        let bridge = FileManager.default.isExecutableFile(atPath: bundled.path) ? bundled : testBridge
        guard FileManager.default.isExecutableFile(atPath: bridge.path) else { throw LabError.message("找不到本機 terminal 執行元件，請重新建置 App。") }
        value.executableURL = bridge; value.arguments = []
        let configured = UserDefaults.standard.string(forKey: "localWorkspace") ?? ""
        let directory = configured.isEmpty ? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("LocalLab/Workspace") : URL(fileURLWithPath: configured)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        value.currentDirectoryURL = directory
        var env = ProcessInfo.processInfo.environment; env["TERM"] = "dumb"; env["PROMPT"] = "%~ %# "; env["PROMPT_EOL_MARK"] = ""
        let custom = UserDefaults.standard.string(forKey: "localPythonExecutable") ?? ""
        let environmentRoot = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("LocalLab/Environments/" + (pythonVersion ?? "3.10.12"))
        let python = custom.isEmpty ? environmentRoot.appendingPathComponent("bin/python3") : URL(fileURLWithPath: custom)
        if FileManager.default.isExecutableFile(atPath: python.path) {
            env["PATH"] = python.deletingLastPathComponent().path + ":" + (env["PATH"] ?? "/usr/bin:/bin")
            if custom.isEmpty { env["VIRTUAL_ENV"] = environmentRoot.path }
        }
        value.environment = env
        value.standardInput = incoming; value.standardOutput = outgoing; value.standardError = outgoing
        outgoing.fileHandleForReading.readabilityHandler = { handle in
            var bytes = [UInt8](repeating: 0, count: 16384)
            let count = Darwin.read(handle.fileDescriptor, &bytes, bytes.count)
            guard count > 0 else { handle.readabilityHandler = nil; return }
            let data = Data(bytes.prefix(count))
            Task { await onText(String(decoding: data, as: UTF8.self)) }
        }
        do { try value.run() } catch { outgoing.fileHandleForReading.readabilityHandler = nil; throw error }
        process = value; input = incoming; output = outgoing
    }
    func send(_ text: String) throws {
        guard let process, process.isRunning, let input else { throw LabError.message("本機 terminal 已結束，請按重新連線。") }
        try input.fileHandleForWriting.write(contentsOf: Data(text.utf8))
    }
    func stop() {
        output?.fileHandleForReading.readabilityHandler = nil
        try? input?.fileHandleForWriting.close()
        if let process, process.isRunning { process.terminate() }
        process = nil; input = nil; output = nil
    }
}

actor RemoteShellTerminal: ShellTerminal {
    private let base: URL
    private let credential: String
    private let session: URLSession
    private var name: String?
    private var socket: URLSessionWebSocketTask?
    private var reader: Task<Void, Never>?
    init(base: URL, credential: String) {
        self.base = base; self.credential = credential
        let configuration = URLSessionConfiguration.ephemeral
        configuration.httpCookieStorage = nil; configuration.urlCache = nil
        session = URLSession(configuration: configuration, delegate: NoRedirect(), delegateQueue: nil)
    }
    private func request(_ method: String, path: String, allowed: Set<Int>) async throws -> (Int, Data) {
        var parts = URLComponents(url: base, resolvingAgainstBaseURL: false)!; parts.path += path
        var request = URLRequest(url: parts.url!); request.httpMethod = method; request.timeoutInterval = 20
        request.setValue("token " + credential, forHTTPHeaderField: "Authorization")
        let (data, response) = try await session.data(for: request)
        guard let status = (response as? HTTPURLResponse)?.statusCode, allowed.contains(status) else { throw LabError.http((response as? HTTPURLResponse)?.statusCode ?? 0) }
        return (status, data)
    }
    func start(onText: @escaping @Sendable (String) async -> Void) async throws {
        guard name == nil else { return }
        let (_, baseline) = try await request("GET", path: "/terminals", allowed: [200])
        let prior = (try JSONSerialization.jsonObject(with: baseline) as? [[String: Any]] ?? []).compactMap { $0["name"] as? String }
        let (_, created) = try await request("POST", path: "/terminals", allowed: [200, 201])
        guard let object = try JSONSerialization.jsonObject(with: created) as? [String: Any], let identifier = object["name"] as? String, !prior.contains(identifier) else { throw LabError.message("伺服器沒有建立新的 App 專用 terminal。") }
        name = identifier
        var parts = URLComponents(url: base, resolvingAgainstBaseURL: false)!; parts.scheme = parts.scheme == "https" ? "wss" : "ws"
        parts.path = String(parts.path.dropLast(4)) + "/terminals/websocket/" + identifier
        let origin = "\(base.scheme!)://\(base.host!)" + (base.port.map { ":\($0)" } ?? "")
        var request = URLRequest(url: parts.url!); request.setValue("token " + credential, forHTTPHeaderField: "Authorization"); request.setValue(origin, forHTTPHeaderField: "Origin")
        let ws = session.webSocketTask(with: request); socket = ws; ws.resume()
        reader = Task {
            do {
                while !Task.isCancelled {
                    let raw = try await ws.receive()
                    let data: Data
                    switch raw { case .string(let text): data = Data(text.utf8); case .data(let bytes): data = bytes; @unknown default: continue }
                    guard let array = try JSONSerialization.jsonObject(with: data) as? [Any], let kind = array.first as? String else { continue }
                    if kind == "stdout", array.count > 1, let text = array[1] as? String { await onText(text) }
                    if kind == "disconnect" { await onText("\n伺服器 terminal 已結束；請重新連線。\n"); return }
                }
            } catch { if !Task.isCancelled { await onText("\nTerminal 連線中斷；請重新連線。\n") } }
        }
        try await socketMessage(["set_size", 28, 100, 0, 0])
    }
    private func socketMessage(_ content: [Any]) async throws {
        guard let socket else { throw LabError.message("伺服器 terminal 尚未連線。") }
        let data = try JSONSerialization.data(withJSONObject: content)
        try await socket.send(.string(String(decoding: data, as: UTF8.self)))
    }
    func send(_ text: String) async throws { try await socketMessage(["stdin", text]) }
    func stop() async throws {
        reader?.cancel(); reader = nil; socket?.cancel(with: .goingAway, reason: nil); socket = nil
        if let name {
            _ = try await request("DELETE", path: "/terminals/" + name, allowed: [204, 404])
            let (status, _) = try await request("GET", path: "/terminals/" + name, allowed: [200, 404])
            guard status == 404 else { throw LabError.message("App 專用 terminal \(name) 尚未確認關閉。") }
            self.name = nil
        }
    }
}
