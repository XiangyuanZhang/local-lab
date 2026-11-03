import Foundation

/// Opt-in integration check: only creates/deletes its own UUID-named remote directory.
@main struct NotebookLiveCheck {
    static func main() async {
        guard CommandLine.arguments.count == 3, CommandLine.arguments[1] == "--live" else { exit(2) }
        let root = URL(fileURLWithPath: CommandLine.arguments[2])
        let folder = "local-lab-notebook-" + UUID().uuidString.prefix(8).lowercased()
        let path = folder + "/Preview.ipynb"
        let client = JupyterClient()
        var madeFolder = false, madeFile = false
        var report: [String: Any] = ["success": false, "folder": folder]
        do {
            try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
            let token = try String(contentsOfFile: "/Applications/Local Lab.app/Contents/Resources/builtin-token.txt", encoding: .utf8).trimmingCharacters(in: .whitespacesAndNewlines)
            let config = URLSessionConfiguration.ephemeral; config.urlCache = nil; config.httpCookieStorage = nil
            let session = URLSession(configuration: config, delegate: NoRedirect(), delegateQueue: nil)
            defer { session.invalidateAndCancel() }
            func http(_ method: String, _ relative: String, _ body: [String: Any]? = nil) async throws -> Int {
                guard relative == folder || relative.hasPrefix(folder + "/") else { throw LabError.message("Test path escaped isolated folder") }
                var u = URLComponents(string: "https://lecture.cs.tum.de:9000/user/go97lep/api/contents/")!; u.path += relative
                var r = URLRequest(url: u.url!); r.httpMethod = method; r.timeoutInterval = 20; r.cachePolicy = .reloadIgnoringLocalCacheData
                r.setValue("token " + token, forHTTPHeaderField: "Authorization")
                if let body { r.httpBody = try JSONSerialization.data(withJSONObject: body); r.setValue("application/json", forHTTPHeaderField: "Content-Type") }
                let (_, response) = try await session.data(for: r)
                return (response as? HTTPURLResponse)?.statusCode ?? 0
            }
            _ = try await client.connect(token: token)
            do {
                try await client.createRemoteDirectory(path: folder); madeFolder = true
                let cells: [[String: Any]] = [
                    ["id": "markdown-qa", "cell_type": "markdown", "metadata": [:], "source": ["# Notebook stays inside Local Lab\n", "**中文文字与 Markdown**\n"]],
                    ["id": "code-qa", "cell_type": "code", "metadata": [:], "source": ["print(42)\n"], "execution_count": 1, "outputs": [["output_type": "stream", "name": "stdout", "text": ["42\n"]]]]
                ]
                let document: [String: Any] = ["nbformat": 4, "nbformat_minor": 5, "metadata": ["language_info": ["name": "python"]], "cells": cells]
                guard try await http("GET", path) == 404 else { throw LabError.message("Test file already exists") }
                let status = try await http("PUT", path, ["type": "notebook", "format": "json", "content": document])
                guard [200, 201].contains(status) else { throw LabError.http(status) }; madeFile = true
                let file = try await client.remoteFile(path)
                let markdown = try NotebookMarkdown.render(file.content)
                guard file.entry.type == "notebook", markdown.contains("Notebook stays inside Local Lab"), markdown.contains("print(42)") else { throw LabError.message("Notebook read/render check failed") }
                var readOnly = false
                do { _ = try await client.saveRemoteFile(path: path, content: "bad replacement", expectedContent: file.content) }
                catch { readOnly = error.localizedDescription.contains("唯讀") }
                let unchanged = try await client.remoteFile(path)
                guard readOnly, unchanged.content == file.content else { throw LabError.message("Read-only guard failed") }
                report["api_read_render_and_readonly"] = true
                try JSONSerialization.data(withJSONObject: ["path": path], options: .prettyPrinted).write(to: root.appendingPathComponent("ready.json"))
                print("READY_FOR_UI: " + path); fflush(stdout)
                let deadline = Date().addingTimeInterval(900)
                while !FileManager.default.fileExists(atPath: root.appendingPathComponent("ui-done.flag").path), Date() < deadline {
                    try await Task.sleep(nanoseconds: 1_000_000_000)
                }
                report["ui_confirmed"] = FileManager.default.fileExists(atPath: root.appendingPathComponent("ui-done.flag").path)
            } catch { report["test_error"] = String(describing: type(of: error)) }
            if madeFile { let deleted = try await http("DELETE", path); let checked = try await http("GET", path); report["file_removed"] = deleted == 204 && checked == 404 }
            if madeFolder { let deleted = try await http("DELETE", folder); let checked = try await http("GET", folder); report["folder_removed"] = deleted == 204 && checked == 404 }
            try await client.disconnect(); report["owned_kernel_cleaned"] = true
            report["success"] = ["api_read_render_and_readonly", "ui_confirmed", "file_removed", "folder_removed", "owned_kernel_cleaned"].allSatisfy { report[$0] as? Bool == true }
        } catch { report["error_type"] = String(describing: type(of: error)); report["error_code"] = (error as NSError).code; try? await client.disconnect() }
        try? JSONSerialization.data(withJSONObject: report, options: [.prettyPrinted, .sortedKeys]).write(to: root.appendingPathComponent("report.json"))
        print("REPORT_SAVED"); fflush(stdout)
        if report["success"] as? Bool != true { exit(1) }
    }
}
