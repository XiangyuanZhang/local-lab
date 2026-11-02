import Foundation
import SwiftUI

struct CheckFailure: Error { let message: String }
private final class FakeKernel: KernelService {
    var owned: String? = "app-owned"
    var cleaned: [String] = []
    var failCleanup = false
    var executeCount = 0
    func connect(token: String) async throws -> ConnectionInfo { ConnectionInfo(kernel: KernelInfo(id: "app-owned", name: "python3"), existingCount: 2, displayName: "Python 3", pythonVersion: "3.10.12") }
    func execute(code: String, onEvent: @escaping @Sendable (KernelEvent) async -> Void) async throws {
        executeCount += 1
        await onEvent(.text("Hello from local API\n", isError: false))
        await onEvent(.completed(success: true))
    }
    func interrupt() async throws {}
    func disconnect() async throws {
        if failCleanup { throw LabError.http(403) }
        if let owned { cleaned.append(owned); self.owned = nil }
    }
    func ownedKernelID() async -> String? { owned }
}
private actor FakeLocalPython: LocalPythonService {
    var success = true
    func setSuccess(_ value: Bool) { success = value }
    func run(code: String, name: String, version: String, onText: @escaping @Sendable (String, Bool) async -> Void) async throws -> Bool { success }
    func interrupt() async {}
}
private final class MemoryVault: TokenVault {
    var value: String?
    var saves = 0
    func read() throws -> String? { value }
    func save(_ token: String) throws { saves += 1; value = token }
    func remove() throws { value = nil }
}
private actor Events {
    var text = ""; var completed = false
    func append(_ event: KernelEvent) {
        switch event { case .text(let value, _): text += value; case .completed(let success): completed = success; default: break }
    }
    func result() -> (String, Bool) { (text, completed) }
}
@main
struct Checks {
    @MainActor static func main() async {
        var passed: [String] = []
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("LocalLabChecks-" + UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        func check(_ condition: Bool, _ message: String) throws { if !condition { throw CheckFailure(message: message) } }
        do {
            for _ in 0..<100 {
                let completion = OneShotContinuation<Int>()
                let result: Int = try await withCheckedThrowingContinuation { continuation in
                    completion.install(continuation)
                    DispatchQueue.concurrentPerform(iterations: 100) { n in
                        completion.resolve(.success(n))
                    }
                }
                try check((0..<100).contains(result), "Concurrent duplicate callback completion failed")
            }
            let early = OneShotContinuation<Int>()
            early.resolve(.success(42))
            let earlyValue: Int = try await withCheckedThrowingContinuation { early.install($0) }
            try check(earlyValue == 42 && !early.resolve(.success(9)), "Early completion or late callback failed")
            let cancelled = OneShotContinuation<Int>()
            cancelled.resolve(.failure(CancellationError()))
            do {
                let _: Int = try await withCheckedThrowingContinuation { cancelled.install($0) }
                throw CheckFailure(message: "Early cancellation was lost")
            } catch is CancellationError {}
            passed.append("heartbeat_10000_duplicate_callbacks_early_completion_and_cancellation")
            let fake = FakeKernel()
            let localGate = FakeLocalPython()
            let store = WorkspaceStore(service: fake, library: DraftLibrary(root: root.appendingPathComponent("state")), localPython: localGate)
            store.run()
            try check(!store.canRun && store.runningID == nil && store.outputs.isEmpty, "Cannot execute without authentication")
            passed.append("unauthenticated_execution_disabled")
            let connected = await store.connect(token: "test-credential")
            try check(connected, "Fake connection failed")
            store.run()
            for _ in 0..<100 { if store.runningID == nil { break }; try await Task.sleep(nanoseconds: 1_000_000) }
            try check(store.outputs[store.selection!]!.compactMap(\.text).joined().contains("Hello from local API\n") && store.runStates[store.selection!] == "本機與伺服器通過", "Execution result mismatch")
                        await localGate.setSuccess(false)
            store.run()
            for _ in 0..<100 { if store.runningID == nil { break }; try await Task.sleep(nanoseconds: 1_000_000) }
            try check(fake.executeCount == 1 && store.runStates[store.selection!] == "本機錯誤 · 未送出" && store.isReady, "Failed local code was sent to server")
            passed.append("local_failure_never_calls_remote_execution")
            await localGate.setSuccess(true)
            let cleaned = await store.disconnect()
            try check(cleaned && fake.cleaned == ["app-owned"] && store.connection == nil, "Wrong kernel cleanup")
            passed.append("execution_state_and_owned_kernel_cleanup")
            fake.owned = "app-owned"; fake.failCleanup = true
            _ = await store.connect(token: "test-credential")
            let failed = await store.disconnect()
            try check(!failed && store.connection?.kernel.id == "app-owned" && store.error?.contains("清理尚未確認") == true && !store.isReady, "Cleanup failure was hidden")
            passed.append("cleanup_failure_preserves_retry_state")
            let library = DraftLibrary(root: root.appendingPathComponent("persistence"))
            let drafts = [ScriptDraft(name: "local.py", code: "print(42)\n")]
            try library.save(drafts)
            try check(library.load() == drafts, "Draft persistence failed")
            let saved = try String(contentsOf: root.appendingPathComponent("persistence/drafts.json"), encoding: .utf8)
            try check(!saved.contains("token") && !saved.contains("test-credential"), "Credential persistence detected")
            passed.append("draft_roundtrip_without_credentials")
            let vault = MemoryVault()
            let credentialStore = WorkspaceStore(service: FakeKernel(), library: DraftLibrary(root: root.appendingPathComponent("credential-state")), vault: vault)
            _ = await credentialStore.connect(token: "synthetic-test-value")
            try check(credentialStore.hasSavedToken && vault.value == "synthetic-test-value", "Credential was not saved through vault")
            let reopened = WorkspaceStore(service: FakeKernel(), library: DraftLibrary(root: root.appendingPathComponent("credential-reopen")), vault: vault)
            let restored = await reopened.connectUsingSavedToken()
            try check(restored && reopened.isReady && vault.saves == 1, "Saved credential was rewritten or not reused")
            reopened.forgetSavedToken()
            try check(vault.value == nil && !reopened.hasSavedToken, "Credential removal failed")
            _ = await credentialStore.disconnect(); _ = await reopened.disconnect()
            passed.append("saved_token_reuse_and_forget")
            if ProcessInfo.processInfo.environment["LOCAL_LAB_VERIFY_KEYCHAIN"] == "1" {
                let nativeVault = KeychainTokenVault(service: "local.edward.LocalLab.test." + UUID().uuidString, account: "synthetic-test")
                defer { try? nativeVault.remove() }
                try nativeVault.save("not-a-real-credential")
                try check((try nativeVault.read()) == "not-a-real-credential", "macOS Keychain roundtrip failed")
                try nativeVault.remove()
                try check((try nativeVault.read()) == nil, "macOS Keychain test item not removed")
                passed.append("native_keychain_synthetic_roundtrip")
            }
            if ProcessInfo.processInfo.environment["LOCAL_LAB_VERIFY_MARKDOWN"] == "1" {
                let resources = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent("Resources")
                let markdown = MarkdownCheck()
                let verified = try await markdown.verify(resources: resources)
                try check(verified, "Markdown rendering or HTML safety check failed")
                passed.append("local_markdown_rendering_safety_and_480_unchanged_updates_render_once")
            }
            if let endpoint = ProcessInfo.processInfo.environment["LOCAL_LAB_TEST_API"], let url = URL(string: endpoint) {
                let client = JupyterClient(base: url)
                let connection = try await client.connect(token: "integration-test-only")
                try check(connection.existingCount == 2 && connection.kernel.id == "app-owned", "REST ownership failed")
                let events = Events()
                try await client.execute(code: "print('Hello from local API')") { event in await events.append(event) }
                let (text, complete) = await events.result()
                try check(text == "Hello from local API\n" && complete, "WebSocket request correlation failed")
                let entries = try await client.remoteDirectory("")
                try check(entries.first?.type == "directory" && entries.contains { $0.path == "Notes.md" }, "Directory order or listing failed")
                let original = try await client.remoteFile("Notes.md")
                try check(original.content == "original remote text", "Remote text read failed")
                let edited = try await client.saveRemoteFile(path: "Notes.md", content: "updated remote text", expectedContent: original.content)
                try check(edited.content == "updated remote text", "Save verification failed")
                var rejected = false
                do { _ = try await client.saveRemoteFile(path: "Notes.md", content: "unsafe overwrite", expectedContent: original.content) }
                catch is RemoteConflict { rejected = true }
                try check(rejected, "Stale version overwrote remote content")
                let retained = try await client.remoteFile("Notes.md")
                try check(retained.content == "updated remote text", "Conflict changed remote data")
                let special = "測試 ?#.py"
                let created = try await client.createRemoteFile(path: special, content: "print(42)\n")
                try check(created.entry.path == special && created.content == "print(42)\n", "Special filename URL encoding failed")
                var duplicateRejected = false
                do { _ = try await client.createRemoteFile(path: special, content: "overwrite") }
                catch { duplicateRejected = true }
                try check(duplicateRejected, "Duplicate create overwrote existing file")
                try await client.createRemoteDirectory(path: "new-folder")
                let rootEntries = try await client.remoteDirectory("")
                try check(rootEntries.contains { $0.path == "new-folder" && $0.type == "directory" }, "Folder creation failed")
                var traversalRejected = false
                do { _ = try RemotePath.validated("../secret") } catch { traversalRejected = true }
                try check(traversalRejected, "Parent traversal allowed")
                passed.append("remote_directory_read_save_conflict_and_special_filenames")
                try await client.interrupt()
                try await client.disconnect()
                let owned = await client.ownedKernelID()
                try check(owned == nil, "REST cleanup failed")
                passed.append("native_REST_WebSocket_parent_filtering_and_cleanup")
                let treeClient = JupyterClient(base: url)
                let treeStore = WorkspaceStore(service: treeClient, library: DraftLibrary(root: root.appendingPathComponent("tree")))
                let treeConnected = await treeStore.connect(token: "integration-test-only")
                try check(treeConnected && treeStore.remoteTreeRoots.contains { $0.path == "Notes.md" }, "Sidebar root failed to sync")
                treeStore.selection = WorkspaceStore.remoteBrowserID
                treeStore.remoteDirectoryPath = "datasets"
                let createdWithoutDraft = await treeStore.createRemoteDocument(name: "新檔案 ?.md")
                let createdPath = "datasets/新檔案 ?.md"
                try check(createdWithoutDraft && treeStore.selected?.remotePath == createdPath && treeStore.selected?.code == "" && treeStore.directoryCache["datasets"]?.contains(where: { $0.path == createdPath }) == true, "Create remote file without selected draft failed")
                let duplicate = await treeStore.createRemoteDocument(name: "新檔案 ?.md")
                try check(!duplicate && treeStore.selected?.remotePath == createdPath, "Duplicate remote file creation was accepted")
                let empty = try await treeClient.remoteFile(createdPath)
                try check(empty.content == "", "Created file contents differ")
                var cleanup = URLRequest(url: url.appendingPathComponent("contents/" + createdPath))
                cleanup.httpMethod = "DELETE"; cleanup.setValue("token integration-test-only", forHTTPHeaderField: "Authorization")
                let (_, cleanupResponse) = try await URLSession.shared.data(for: cleanup)
                try check((cleanupResponse as? HTTPURLResponse)?.statusCode == 204, "Created test file cleanup failed")
                treeStore.remoteDirectoryPath = ""; treeStore.selection = WorkspaceStore.remoteBrowserID
                await treeStore.refreshRemote()
                passed.append("create_remote_file_in_subfolder_without_local_draft_and_reject_duplicate")
                treeStore.expandFolder("datasets", expanded: true)
                for _ in 0..<200 { if !treeStore.loadingRemoteFolders.contains("datasets") { break }; try await Task.sleep(nanoseconds: 1_000_000) }
                guard let child = treeStore.directoryCache["datasets"]?.first else { throw CheckFailure(message: "Folder expansion did not load children") }
                treeStore.selection = treeStore.remoteSelectionID(child)
                await treeStore.handleSelection()
                try check(treeStore.selected?.remotePath == "datasets/data.py" && treeStore.selected?.code == "print(7)\n", "Sidebar selection failed to open remote file")
                treeStore.updateCode("local unsaved edit")
                _ = try await treeClient.saveRemoteFile(path: child.path, content: "changed on remote", expectedContent: "print(7)\n")
                await treeStore.refreshRemote()
                try check(treeStore.selected?.code == "local unsaved edit" && treeStore.conflicts[treeStore.selection!] != nil, "Remote refresh overwrote unsaved sidebar file")
                treeStore.resolveConflictKeepingCopy()
                try check(treeStore.selected?.code == "changed on remote" && treeStore.drafts.contains { $0.remotePath == nil && $0.code == "local unsaved edit" }, "Conflict resolution lost local draft")
                let deletedID = treeStore.selection
                treeStore.updateCode("unsaved content before remote deletion")
                var deleteRequest = URLRequest(url: url.appendingPathComponent("contents/datasets/data.py"))
                deleteRequest.httpMethod = "DELETE"
                deleteRequest.setValue("token integration-test-only", forHTTPHeaderField: "Authorization")
                let (_, deletedResponse) = try await URLSession.shared.data(for: deleteRequest)
                try check((deletedResponse as? HTTPURLResponse)?.statusCode == 204, "Mock deletion failed")
                await treeStore.refreshRemote()
                try check(treeStore.selected?.remotePath == nil && treeStore.selected?.code == "unsaved content before remote deletion" && treeStore.selection != deletedID && treeStore.selected?.name == "data.deleted-copy.py" && treeStore.directoryCache["datasets"]?.isEmpty == true, "Deleted remote file did not become a preserved local copy")
                passed.append("remote_deletion_preserves_unsaved_local_content_and_removes_sidebar_item")
                let treeCleaned = await treeStore.disconnect()
                try check(treeCleaned, "Sidebar session cleanup failed")
                passed.append("sidebar_folder_loading_selection_and_unsaved_conflict_preservation")
            }
            if let pythonPath = ProcessInfo.processInfo.environment["LOCAL_LAB_TEST_PYTHON"] {
                UserDefaults.standard.set(pythonPath, forKey: "localPythonExecutable")
                UserDefaults.standard.set(root.appendingPathComponent("local-workspace").path, forKey: "localWorkspace")
                defer { UserDefaults.standard.removeObject(forKey: "localPythonExecutable"); UserDefaults.standard.removeObject(forKey: "localWorkspace") }
                let runner = LocalPythonRunner(root: root.appendingPathComponent("python"))
                let collected = Events()
                let ok = try await runner.run(code: "print('LOCAL_LIGHT_OK')", name: "success.py", version: "3.10.12") { text, isError in await collected.append(.text(text, isError: isError)) }
                try check(ok, "Real Python success failed")
                let bad = try await runner.run(code: "value = 1\nraise ValueError('LOCAL_LIGHT_FAILURE')", name: "failure.py", version: "3.10.12") { text, isError in await collected.append(.text(text, isError: isError)) }
                let (localOutput, _) = await collected.result()
                try check(!bad && localOutput.contains("LOCAL_LIGHT_OK") && localOutput.contains("failure.py\", line 2") && localOutput.contains("ValueError: LOCAL_LIGHT_FAILURE"), "Local traceback filename or line missing")
                var mismatch = false
                do { _ = try await runner.run(code: "print('MUST_NOT_RUN')", name: "mismatch.py", version: "3.11.0") { _, _ in } }
                catch { mismatch = error.localizedDescription.contains("版本不一致") }
                try check(mismatch, "Wrong Python version allowed")
                passed.append("real_python_exact_version_success_failure_traceback_and_mismatch")
                let shell = LocalShellTerminal()
                let shellEvents = Events()
                try await shell.start { text in await shellEvents.append(.text(text, isError: false)) }
                try await shell.send("export LOCAL_LAB_LIGHT_VALUE=37; printf 'LOCAL_SHELL_%s\\n' \"$LOCAL_LAB_LIGHT_VALUE\"\n")
                for _ in 0..<100 { let (text, _) = await shellEvents.result(); if text.contains("LOCAL_SHELL_37") { break }; try await Task.sleep(nanoseconds: 20_000_000) }
                try await shell.send("printf 'LOCAL_STATE_%s\\n' \"$LOCAL_LAB_LIGHT_VALUE\"\n")
                for _ in 0..<100 { let (text, _) = await shellEvents.result(); if text.contains("LOCAL_STATE_37") { break }; try await Task.sleep(nanoseconds: 20_000_000) }
                try await shell.send("read -r local_reply; printf 'LOCAL_READ_%s\\n' \"$local_reply\"\n")
                try await shell.send("light-read-42\n")
                for _ in 0..<100 { let (text, _) = await shellEvents.result(); if text.contains("LOCAL_READ_light-read-42") { break }; try await Task.sleep(nanoseconds: 20_000_000) }
                let (shellOutput, _) = await shellEvents.result(); await shell.stop()
                try check(shellOutput.contains("LOCAL_SHELL_37") && shellOutput.contains("LOCAL_STATE_37") && shellOutput.contains("LOCAL_READ_light-read-42"), "Local shell state or IO failed")
                passed.append("local_terminal_input_output_and_persistent_state")
            }
            if ProcessInfo.processInfo.environment["LOCAL_LAB_VERIFY_TUM_TLS"] == "1" {
                let session = URLSession(configuration: .ephemeral)
                let (data, response) = try await session.data(from: URL(string: "https://lecture.cs.tum.de:9000/user/go97lep/api")!)
                let object = try JSONSerialization.jsonObject(with: data) as? [String: String]
                try check((response as? HTTPURLResponse)?.statusCode == 200 && object?["version"] != nil, "TUM TLS/API version failed")
                passed.append("native_TLS_TUM_public_API_version")
            }
            print(String(decoding: try JSONSerialization.data(withJSONObject: ["success": true, "passed": passed], options: [.prettyPrinted, .sortedKeys]), as: UTF8.self))
        } catch {
            let reason = (error as? CheckFailure)?.message ?? String(describing: type(of: error))
            print("CHECK FAILED: " + reason)
            let diagnostic = error as NSError
            print("TEST DIAGNOSTIC: \(diagnostic.domain) \(diagnostic.code) \(diagnostic.localizedDescription)")
            exit(1)
        }
    }
}
