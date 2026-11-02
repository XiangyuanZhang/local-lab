import Foundation

private actor Collected {
    var stdout = ""; var stderr = ""; var image: Data?; var complete = false
    func receive(_ event: KernelEvent) {
        switch event {
        case .text(let text, let error): if error { stderr += text } else { stdout += text }
        case .image(let data): image = data
        case .completed(let success): complete = success
        case .clear: stdout = ""; stderr = ""; image = nil
        }
    }
    func values() -> (String,String,Data?,Bool) { (stdout,stderr,image,complete) }
}
private final class NoRedirectForCheck: NSObject, URLSessionTaskDelegate {
    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse, newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void) { completionHandler(nil) }
}
enum AppLiveVerifier {
    static func run(credential: String, root: URL) async -> URL {
        let output = root.appendingPathComponent("outputs/app-test")
        try? FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
        let signal = root.appendingPathComponent("work/live-ui-done.flag")
        let ready = root.appendingPathComponent("work/live-test-ready.json")
        let folder = "local-lab-check-" + UUID().uuidString.prefix(8).lowercased()
        var report: [String:Any] = ["started_at":ISO8601DateFormatter().string(from:Date()),"test_folder":folder,"success":false]
        var steps: [[String:Any]] = []
        var token = ""; var terminal: String?; var createdFiles: [String] = []; var createdFolder = false
        let client = JupyterClient()
        let config = URLSessionConfiguration.ephemeral; config.httpCookieStorage = nil; config.urlCache = nil
        config.timeoutIntervalForRequest = 20; config.timeoutIntervalForResource = 40
        let session = URLSession(configuration: config, delegate: NoRedirectForCheck(), delegateQueue: nil)
        let api = "https://lecture.cs.tum.de:9000/user/go97lep/api"
        func add(_ name: String, _ success: Bool, _ extra: [String:Any] = [:]) {
            var item = extra; item["test"] = name; item["success"] = success; steps.append(item)
            print("\(name): \(success ? "PASS" : "FAIL")",flush:true)
        }
        func http(_ method: String, _ path: String, _ body: [String:Any]? = nil) async throws -> (Int,Data) {
            var parts = URLComponents(string: api)!
            parts.path += path
            var request = URLRequest(url: parts.url!); request.httpMethod = method
            request.setValue("token " + token, forHTTPHeaderField:"Authorization")
            if let body { request.httpBody = try JSONSerialization.data(withJSONObject: body); request.setValue("application/json",forHTTPHeaderField:"Content-Type") }
            let (data,response) = try await session.data(for:request)
            guard let response = response as? HTTPURLResponse else { throw LabError.message("No HTTP response") }
            return (response.statusCode,data)
        }
        func check(_ value: Bool, _ message: String) throws { if !value { throw LabError.message(message) } }
        do {
            guard !credential.isEmpty else { throw LabError.message("App is not authenticated") }
            token = credential
            let connected = try await client.connect(token: token)
            report["test_kernel_id"] = connected.kernel.id; report["existing_kernel_count"] = connected.existingCount
            add("authenticated_connection",true)
            try await client.createRemoteDirectory(path: folder); createdFolder = true
            add("create_directory",true)
            let py = folder + "/command-check.py"
            let v1 = "print('APP_CHECK_V1')\n"
            _ = try await client.createRemoteFile(path: py, content: v1); createdFiles.append(py)
            let first = try await client.remoteFile(py)
            try check(first.content == v1,"Created file did not match")
            add("create_file_and_readback",true)
            let v2 = """
            print('APP_CHECK_STDOUT_V2')
            import sys, io
            print('APP_CHECK_STDERR_V2', file=sys.stderr)
            import matplotlib
            matplotlib.use('Agg')
            import matplotlib.pyplot as plt
            from IPython.display import display, Image
            fig, ax = plt.subplots(figsize=(5, 2.6))
            ax.plot([1, 2, 3, 4], [1, 4, 9, 16], marker='o', color='#007aff')
            ax.set_title('Local Lab output check')
            ax.set_xlabel('x'); ax.set_ylabel('x squared')
            fig.tight_layout()
            image_bytes = io.BytesIO()
            fig.savefig(image_bytes, format='png')
            display(Image(data=image_bytes.getvalue()))
            plt.close(fig)
            """ + "\n"
            let edited = try await client.saveRemoteFile(path: py,content:v2,expectedContent:v1)
            try check(edited.content == v2,"Modified file did not match")
            add("modify_file_and_readback",true)
            let collected = Collected()
            try await client.execute(code:"import runpy\nrunpy.run_path(" + String(data:try JSONSerialization.data(withJSONObject:[py],options:[.withoutEscapingSlashes]),encoding:.utf8)!.dropFirst().dropLast() + ")") { event in await collected.receive(event) }
            let (stdout,stderr,image,completed) = await collected.values()
            let runPassed = completed && stdout.contains("APP_CHECK_STDOUT_V2") && stderr.contains("APP_CHECK_STDERR_V2")
            add("run_file_stdout_stderr",runPassed,["stdout":stdout,"stderr":stderr,"execute_reply_ok_and_idle":completed])
            let validPNG = image?.starts(with:[137,80,78,71,13,10,26,10]) == true
            try image?.write(to: output.appendingPathComponent("kernel-output.png"))
            add("kernel_PNG_display_data",validPNG,["bytes":image?.count ?? 0])
            let md = folder + "/render-check.md"
            let markdown = """
            # Local Lab Render Check

            **Bold text** and *italic text* render locally.

            ## Table

            | Test | Result |
            | --- | --- |
            | Command | Returned |
            | Markdown | Rendered |

            > This is a block quote.

            - [x] File readback
            - [x] WebSocket output

            ```python
            print('Markdown code block')
            ```
            """ + "\n"
            _ = try await client.createRemoteFile(path:md,content:markdown); createdFiles.append(md)
            add("create_markdown_fixture",true)
            do {
                let (listStatus,listData) = try await http("GET","/terminals")
                try check(listStatus == 200,"Terminal listing returned HTTP \(listStatus)")
                let baseline = (try JSONSerialization.jsonObject(with:listData) as? [[String:Any]] ?? []).compactMap { $0["name"] as? String }
                let (createdStatus,terminalData) = try await http("POST","/terminals",[:])
                try check([200,201].contains(createdStatus),"Terminal creation returned HTTP \(createdStatus)")
                let object = try JSONSerialization.jsonObject(with:terminalData) as? [String:Any]
                guard let name = object?["name"] as? String, !baseline.contains(name) else { throw LabError.message("No distinct terminal returned") }
                terminal = name
                var request = URLRequest(url:URL(string:"wss://lecture.cs.tum.de:9000/user/go97lep/terminals/websocket/"+name)!)
                request.setValue("token " + token,forHTTPHeaderField:"Authorization")
                request.setValue("https://lecture.cs.tum.de:9000",forHTTPHeaderField:"Origin")
                let ws = session.webSocketTask(with:request); ws.resume()
                defer { ws.cancel(with:.normalClosure,reason:nil) }
                func send(_ value: [Any]) async throws { try await ws.send(.string(String(decoding:try JSONSerialization.data(withJSONObject:value),as:UTF8.self))) }
                try await send(["set_size",24,100,0,0])
                let input = "input-"+UUID().uuidString.prefix(8).lowercased()
                try await send(["stdin","printf 'TERM_RESULT_%s\\n' \"$((123*7))\"; printf 'TERM_ERROR_%s\\n' \"$((123*7+1))\" >&2; read -r lab_response; printf 'INPUT_REPLY_%s\\n' \"$lab_response\"\r"])
                try await send(["stdin",input+"\r"])
                let verified = try await withThrowingTaskGroup(of:Bool.self) { group in
                    group.addTask {
                        var text = ""
                        while true {
                            let received = try await ws.receive()
                            guard case .string(let raw) = received, let data = raw.data(using:.utf8), let array = try JSONSerialization.jsonObject(with:data) as? [Any], array.first as? String == "stdout", let chunk = array.dropFirst().first as? String else { continue }
                            text += chunk
                            let plain = text.replacingOccurrences(of: "\u{001B}\\[[0-9;?]*[A-Za-z]", with: "", options: .regularExpression).replacingOccurrences(of: "\r", with: "")
                            if plain.contains("TERM_RESULT_861") && plain.contains("TERM_ERROR_862") && plain.contains("INPUT_REPLY_"+input) { return true }
                            if text.count > 1_048_576 { throw LabError.message("Terminal output exceeded test limit") }
                        }
                    }
                    group.addTask { try await Task.sleep(nanoseconds:20_000_000_000); ws.cancel(with:.goingAway,reason:nil); throw LabError.message("Terminal WebSocket test timed out") }
                    let value = try await group.next() ?? false; group.cancelAll(); return value
                }
                add("terminal_API_WebSocket_input_output",verified,["stdout_marker":"TERM_RESULT_861","stderr_marker":"TERM_ERROR_862","interactive_input_reply_verified":verified,"native_terminal_UI":"not_implemented"])
            } catch {
                add("terminal_API_WebSocket_input_output",false,["error":(error as? LabError)?.localizedDescription ?? String(describing:type(of:error)),"native_terminal_UI":"not_implemented"])
            }
            try JSONSerialization.data(withJSONObject:["folder":folder,"python_path":py,"markdown_path":md],options:.prettyPrinted).write(to:ready)
            print("READY_FOR_UI_CHECK: " + folder,flush:true)
            let deadline = Date().addingTimeInterval(600)
            while !FileManager.default.fileExists(atPath:signal.path) && Date() < deadline { try await Task.sleep(nanoseconds:1_000_000_000) }
            add("UI_check_signal_received",FileManager.default.fileExists(atPath:signal.path))
        } catch {
            add("test_error",false,["error":(error as? LabError)?.localizedDescription ?? String(describing:type(of:error))])
        }
        if let terminal {
            do {
                let (deleted,_) = try await http("DELETE","/terminals/"+terminal)
                let (verified,_) = try await http("GET","/terminals/"+terminal)
                add("test_terminal_cleanup",deleted == 204 && verified == 404,["delete_http":deleted,"verify_http":verified])
            } catch { add("test_terminal_cleanup",false) }
        }
        for file in createdFiles.reversed() {
            do {
                let (deleted,_) = try await http("DELETE","/contents/"+file)
                let (verified,_) = try await http("GET","/contents/"+file)
                add("delete_test_file_and_verify",deleted == 204 && verified == 404,["path":file,"delete_http":deleted,"verify_http":verified])
            } catch { add("delete_test_file_and_verify",false,["path":file]) }
        }
        if createdFolder {
            do { let (status,_) = try await http("DELETE","/contents/"+folder); let (check,_) = try await http("GET","/contents/"+folder); add("delete_test_directory_and_verify",status == 204 && check == 404) }
            catch { add("delete_test_directory_and_verify",false) }
        }
        do { try await client.disconnect(); add("test_kernel_cleanup",true) } catch { add("test_kernel_cleanup",false) }
        token = ""
        report["steps"] = steps; report["success"] = steps.allSatisfy { $0["success"] as? Bool == true }
        report["finished_at"] = ISO8601DateFormatter().string(from:Date())
        try? JSONSerialization.data(withJSONObject:report,options:[.prettyPrinted,.sortedKeys]).write(to:output.appendingPathComponent("live-api-results.json"))
        print("REPORT_SAVED",flush:true)
        return output.appendingPathComponent("live-api-results.json")
    }
}
private func print(_ text: String, flush: Bool) { Swift.print(text); if flush { fflush(stdout) } }
