import Foundation
import SwiftUI

private struct AICheckFailure: Error { let message: String }
private final class AIWorkspaceKernel: KernelService {
    var executeCount = 0
    func connect(token: String) async throws -> ConnectionInfo { throw AIReviewError.network(0) }
    func execute(code: String, onEvent: @escaping @Sendable (KernelEvent) async -> Void) async throws { executeCount += 1 }
    func interrupt() async throws {}
    func disconnect() async throws {}
    func ownedKernelID() async -> String? { nil }
}
private actor FixtureAIService: AIReviewService {
    private(set) var requests: [AIReviewRequest] = []
    var delay: UInt64
    init(delay: UInt64 = 0) { self.delay = delay }
    func review(_ request: AIReviewRequest, configuration: AIReviewConfiguration, key: String) async throws -> AIReviewResponse {
        requests.append(request)
        if delay > 0 {
            let duration = delay
            await Task.detached { try? await Task.sleep(nanoseconds: duration) }.value
        }
        return AIReviewResponse(summary: "fixture review", findings: [], replacementCode: "print('AI_REVIEW_FIXED')\n", metrics: AIRequestMetrics(usage: AIUsage(prompt_tokens: 120, completion_tokens: 30, total_tokens: 150), model: "fixture-reported", elapsed: 2))
    }
    func count() -> Int { requests.count }
}

@main struct AIReviewChecks {
    @MainActor static func main() async {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("LocalLab-AI-Checks-" + UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        var passed: [String] = []
        func check(_ value: Bool, _ message: String) throws { if !value { throw AICheckFailure(message: message) } }
        func expect(_ message: String, _ action: () throws -> Void) throws {
            do { try action() } catch is AIReviewError { return }
            throw AICheckFailure(message: message)
        }
        func wait(_ store: AIReviewStore) async throws {
            for _ in 0..<400 { if !store.isRunning { return }; try await Task.sleep(nanoseconds: 5_000_000) }
            throw AICheckFailure(message: "AI store failed to settle")
        }
        func request(mode: AIReviewMode = .reviewOnly) -> AIReviewRequest {
            AIReviewRequest(snapshot: AIReviewSnapshot(ScriptDraft(name: "sample.py", code: "print(1 / 0)\n")), persona: AIReviewPersona.defaults[0], mode: mode, instruction: "find bugs")
        }
        func envelope(_ payload: [String: Any], reason: String = "stop") throws -> Data {
            let content = String(decoding: try JSONSerialization.data(withJSONObject: payload), as: UTF8.self)
            return try JSONSerialization.data(withJSONObject: ["choices": [["finish_reason": reason, "message": ["content": content]]]])
        }
        do {
            let repository = AIReviewRepository(directory: root.appendingPathComponent("AIReview"))
            let defaults = try repository.load()
            try check(defaults.baseURL == "https://api.deepseek.com" && defaults.mode == .reviewOnly && defaults.personas.count == 3, "Default provider or personas incorrect")
            var config = defaults
            let custom = AIReviewPersona(id: UUID(), name: "課程審閱者", instructions: "不要引入外部套件，保留原本的格式。")
            config.personas.append(custom); config.selectedPersonaID = custom.id; config.mode = .edit
            config.model = "custom-model"
            try repository.save(config); try repository.saveKey("test-ai-only", for: config.baseURL)
            let reloaded = AIReviewRepository(directory: repository.directory)
            try check(try reloaded.load() == config && reloaded.key(for: config.baseURL) == "test-ai-only", "Configuration or key not persisted across launch")
            let settings = try String(contentsOf: repository.directory.appendingPathComponent("settings.json"), encoding: .utf8)
            try check(!settings.contains("test-ai-only"), "API key leaked into persona configuration")
            for (path, permission) in [(repository.directory, 0o700), (repository.directory.appendingPathComponent("settings.json"), 0o600), (repository.directory.appendingPathComponent("api-keys.json"), 0o600)] {
                let attrs = try FileManager.default.attributesOfItem(atPath: path.path)
                try check((attrs[.posixPermissions] as? NSNumber)?.intValue == permission, "Local privacy permissions incorrect")
            }
            passed.append("persona_selection_mode_model_and_key_persist_with_0700_0600_permissions")
            try check(try reloaded.key(for: "https://other.example/v1") == nil, "Credential crossed endpoint boundary")
            try check(try AIEndpoint("https://api.deepseek.com/").scope == AIEndpoint("https://api.deepseek.com/chat/completions/").scope, "Equivalent endpoint scopes differ")
            try check(try AIEndpoint("https://example.org/v1").completions.absoluteString == "https://example.org/v1/chat/completions", "Endpoint path malformed")
            for bad in ["http://example.com", "https://user:pass@example.com", "https://example.com?key=secret", "file:///tmp/test", "https://example.com/#fragment"] {
                try expect("Unsafe endpoint accepted") { _ = try AIEndpoint(bad) }
            }
            try expect("Header injection key accepted") { try repository.saveKey("bad\nkey", for: config.baseURL) }
            try reloaded.removeKey(for: config.baseURL)
            try check(try repository.key(for: config.baseURL) == nil, "Key removal failed")
            try repository.saveKey("test-ai-only", for: config.baseURL)
            passed.append("endpoint_isolation_normalization_https_validation_and_key_removal")
            var invalid = config; invalid.personas = []
            try expect("Empty persona collection accepted") { try repository.save(invalid) }
            invalid = config; invalid.personas[0].name = ""
            try expect("Empty persona name accepted") { try repository.save(invalid) }
            invalid = config; invalid.personas[0].instructions = String(repeating: "a", count: 16_385)
            try expect("Oversized persona accepted") { try repository.save(invalid) }
            passed.append("persona_validation_preserves_last_valid_configuration")
            let wire = try AIReviewPrompt.body(request(), configuration: defaults)
            let body = try JSONSerialization.jsonObject(with: wire) as! [String: Any]
            let messages = body["messages"] as! [[String: String]]
            try check(messages.count == 2 && messages[0]["content"]!.contains(defaults.selectedPersona.instructions) && messages[0]["content"]!.contains("replacement_code MUST be null"), "Persona or mode missing from system prompt")
            let context = try JSONSerialization.jsonObject(with: messages[1]["content"]!.data(using: .utf8)!) as! [String: String]
            try check(context["source_code"] == request().snapshot.code && context["review_request"] == "find bugs" && !String(decoding: wire, as: UTF8.self).contains("test-ai-only"), "Request sent unrelated content or secret")
            var huge = request(); huge = AIReviewRequest(snapshot: AIReviewSnapshot(ScriptDraft(name: "huge.py", code: String(repeating: "x", count: 131_073))), persona: huge.persona, mode: .edit, instruction: "")
            try expect("Oversized code sent") { _ = try AIReviewPrompt.body(huge, configuration: defaults) }
            passed.append("system_persona_mode_and_current_file_only_request_contract_and_input_limits")
            let payload: [String: Any] = ["summary": "one bug", "findings": [], "replacement_code": "print('AI_REVIEW_FIXED')\n"]
            let reviewed = try AIReviewClient.parse(envelope(payload), request: request())
            try check(reviewed.replacementCode == nil, "Review-only response retained injected edit")
            let edited = try AIReviewClient.parse(envelope(payload), request: request(mode: .edit))
            try check(edited.replacementCode == "print('AI_REVIEW_FIXED')\n", "Edit response lost proposed content")
            try expect("Truncated response accepted") { _ = try AIReviewClient.parse(envelope(payload, reason: "length"), request: request(mode: .edit)) }
            try expect("Tool-call response accepted") { _ = try AIReviewClient.parse(envelope(payload, reason: "tool_calls"), request: request(mode: .edit)) }
            var bad = payload; bad["summary"] = " "
            try expect("Empty summary accepted") { _ = try AIReviewClient.parse(envelope(bad), request: request()) }
            bad = payload; bad["findings"] = [["severity": "high", "line": 999, "title": "bad", "detail": "bad"]]
            try expect("Out-of-range source location accepted") { _ = try AIReviewClient.parse(envelope(bad), request: request()) }
            passed.append("review_only_strips_edits_and_malformed_truncated_tool_responses_rejected")
            let usageWire = try JSONSerialization.data(withJSONObject: ["model": "reported-model", "usage": ["prompt_tokens": 120, "completion_tokens": 30, "total_tokens": 150]])
            var measured = AIRequestMetrics.decode(usageWire); measured.elapsed = 2
            try check(measured.usage?.total_tokens == 150 && measured.model == "reported-model" && measured.tokensPerSecond == 75, "Usage or average consumption rate incorrect")
            var session = AIUsageSession(); session.record(measured); session.record(measured)
            try check(session.totalTokens == 300 && session.lastText == "150" && session.speedText == "75.0 tok/s", "Launch accumulation incorrect")
            session.record(AIRequestMetrics())
            try check(session.unknownRequests == 1 && session.totalText == "≥300" && session.lastText == "—" && session.speedText == "— tok/s", "Unknown consumption represented as a false zero")
            try check(AIUsageSession().totalTokens == 0, "Usage persisted into a fresh launch")
            let invalidUsage = try JSONSerialization.data(withJSONObject: ["usage": ["prompt_tokens": -1, "completion_tokens": 3, "total_tokens": 2]])
            try check(AIRequestMetrics.decode(invalidUsage).usage == nil, "Negative usage accepted")
            measured.elapsed = 0; try check(measured.tokensPerSecond == nil, "Zero duration divided")
            passed.append("usage_validation_launch_total_unknown_counts_and_monotonic_average_speed")
            let battery = BatteryStatus.read([["Type": "UPS"], ["Type": "InternalBattery", "Current Capacity": 78, "Max Capacity": 100, "Is Charging": true, "Power Source State": "AC Power"]])
            try check(battery.percent == 78 && battery.charging && battery.onACPower && battery.symbol == "battery.100percent.bolt", "Battery source or charging state incorrect")
            try check(BatteryStatus.read([]).percent == nil && BatteryStatus.read([["Type": "InternalBattery", "Current Capacity": 20, "Max Capacity": 0]]).percent == nil, "Missing or invalid battery invented a percentage")
            passed.append("battery_normalization_internal_source_charging_and_absent_hardware")
            let kernel = AIWorkspaceKernel()
            let workspace = WorkspaceStore(service: kernel, library: DraftLibrary(root: root.appendingPathComponent("Workspace")))
            let draft = ScriptDraft(name: "remote.py", code: "print(1 / 0)\n", remotePath: "remote.py", remoteModified: "baseline", remoteBaseContent: "print(1 / 0)\n")
            workspace.drafts = [draft]; workspace.selection = draft.id
            let editRequest = AIReviewRequest(snapshot: AIReviewSnapshot(draft), persona: custom, mode: .edit, instruction: "")
            let result = AIReviewResult(request: editRequest, response: edited, model: "fixture", provider: "fixture")
            let reviewResult = AIReviewResult(request: AIReviewRequest(snapshot: AIReviewSnapshot(draft), persona: custom, mode: .reviewOnly, instruction: ""), response: edited, model: "fixture", provider: "fixture")
            try expect("Review-only applied to editor") { try workspace.applyAIProposal(reviewResult) }
            workspace.updateCode("user changed content")
            try expect("Concurrent edit overwritten") { try workspace.applyAIProposal(result) }
            workspace.updateCode(draft.code); workspace.selection = nil
            try expect("Different document selection overwritten") { try workspace.applyAIProposal(result) }
            workspace.selection = draft.id; workspace.runningID = draft.id
            try expect("Running code changed") { try workspace.applyAIProposal(result) }
            workspace.runningID = nil; workspace.fileBusy = true
            try expect("Syncing code changed") { try workspace.applyAIProposal(result) }
            workspace.fileBusy = false
            try workspace.applyAIProposal(result)
            try check(workspace.selected?.code == edited.replacementCode && workspace.selected?.isRemoteDirty == true && workspace.selected?.remoteBaseContent == draft.code && kernel.executeCount == 0, "Apply ran code or changed server baseline")
            workspace.updateCode("new edit after apply")
            try expect("Undo overwrote newer edit") { try workspace.undoAIProposal(result) }
            workspace.updateCode(edited.replacementCode!); try workspace.undoAIProposal(result)
            try check(workspace.selected?.code == draft.code, "Undo did not restore original file")
            passed.append("apply_is_explicit_review_only_denied_stale_selection_running_sync_guards_and_safe_undo")
            let service = FixtureAIService()
            let store = AIReviewStore(repository: repository, service: service)
            store.start(draft: draft); try await wait(store)
            try check(store.result?.request.persona == custom && store.result?.request.mode == .edit && workspace.selected?.code == draft.code, "Stored persona not automatically used or result auto-applied")
            store.selectMode(.reviewOnly)
            try check(!store.apply(result, to: workspace) && workspace.selected?.code == draft.code, "Mode switch allowed old edit result")
            store.selectMode(.edit)
            try check(store.apply(result, to: workspace), "Explicit store apply failed")
            store.undo(in: workspace)
            try check(store.lastApplied == nil && workspace.selected?.code == draft.code, "Store undo failed")
            try check(store.usage.totalTokens == 150 && store.statusModel == "fixture-reported", "Store did not publish measured usage/model")
            store.start(draft: draft); try await wait(store)
            try check(store.usage.totalTokens == 300 && AIReviewStore(repository: repository, service: service).usage.totalTokens == 0, "Store launch accounting not isolated")
            let count = await service.count(); try check(count == 2, "Unexpected background AI requests")
            passed.append("store_reuses_saved_persona_and_key_no_autoapply_or_background_requests")
            let delayed = AIReviewStore(repository: repository, service: FixtureAIService(delay: 100_000_000))
            delayed.start(draft: draft); delayed.cancel()
            try await Task.sleep(nanoseconds: 200_000_000)
            try check(!delayed.isRunning && delayed.result == nil && delayed.notice == "已取消", "Cancelled request published late result")
            try check(delayed.usage.unknownRequests == 1 && delayed.usage.totalTokens == 0, "Cancelled/late response counted twice")
            let emptyRepo = AIReviewRepository(directory: root.appendingPathComponent("NoKey"))
            let missing = AIReviewStore(repository: emptyRepo, service: service)
            missing.start(draft: draft)
            try check(!missing.isRunning && missing.showSettings && missing.result == nil, "Missing key sent request")
            passed.append("cancel_ignores_late_result_and_missing_key_opens_settings_without_request")
            let diff = AIReviewDiff(before: String(repeating: "old\n", count: 4000), after: String(repeating: "new\n", count: 4000))
            try check(diff.lines.count == 500 && diff.omitted > 0, "Diff preview is not bounded")
            passed.append("bounded_changed_block_preview_handles_large_files")
            if let endpoint = ProcessInfo.processInfo.environment["LOCAL_LAB_TEST_AI_ENDPOINT"] {
                let client = AIReviewClient(); var network = defaults; network.baseURL = endpoint; network.model = "review-fixture"
                let response = try await client.review(request(), configuration: network, key: "test-ai-only")
                try check(response.metrics.usage?.total_tokens == 150 && (response.metrics.elapsed ?? 0) > 0 && response.metrics.model == "fixture-reported", "Real transport metrics missing")
                try check(response.findings.count == 1 && response.replacementCode == nil, "HTTP review fixture failed")
                network.model = "edit-fixture"
                let responseEdit = try await client.review(request(mode: .edit), configuration: network, key: "test-ai-only")
                try check(responseEdit.replacementCode?.contains("AI_REVIEW_FIXED") == true, "HTTP edit fixture failed")
                for (model, code) in [("unauthorized",401),("rate-limit",429),("server-error",500),("redirect",307)] {
                    network.model = model
                    do {
                        _ = try await client.review(request(), configuration: network, key: "test-ai-only")
                        throw AICheckFailure(message: "HTTP failure was accepted")
                    } catch let error as AIReviewError {
                        guard case .http(let status) = error else { throw AICheckFailure(message: "Unexpected HTTP error type") }
                        try check(status == code && !error.localizedDescription.contains("test-ai-only") && !error.localizedDescription.contains("sensitive-body"), "Error body or key leaked")
                    }
                }
                for model in ["truncated", "empty", "invalid-json", "malformed-envelope", "tool-call", "oversize"] {
                    network.model = model
                    do { _ = try await client.review(request(mode: .edit), configuration: network, key: "test-ai-only"); throw AICheckFailure(message: "Bad HTTP response accepted: " + model) }
                    catch let measured as AIMeasuredFailure {
                        try check(model == "malformed-envelope" ? measured.metrics.usage == nil : measured.metrics.usage?.total_tokens == 150, "Rejected result lost provider usage")
                    }
                    catch is AIReviewError {}
                }
                network.model = "slow"
                let cancellationConfig = network
                let pending = Task { try await client.review(request(), configuration: cancellationConfig, key: "test-ai-only") }
                try await Task.sleep(nanoseconds: 50_000_000); pending.cancel()
                do { _ = try await pending.value; throw AICheckFailure(message: "HTTP cancellation ignored") } catch is CancellationError {}
                var parts = URLComponents(string: endpoint)!; parts.path = "/metrics"
                let (metrics, _) = try await URLSession.shared.data(from: parts.url!)
                try check((try JSONSerialization.jsonObject(with: metrics) as? [String: Int])?["redirect_leaks"] == 0, "Credential redirect followed")
                passed.append("real_URLSession_loopback_review_edit_http_errors_redirect_isolation_limits_truncation_and_cancellation")
            }
            let output: [String: Any] = ["success": true, "passed": passed, "real_provider_called": false]
            print(String(decoding: try JSONSerialization.data(withJSONObject: output, options: [.prettyPrinted, .sortedKeys]), as: UTF8.self))
        } catch {
            let reason = (error as? AICheckFailure)?.message ?? (error as? AIReviewError)?.localizedDescription ?? String(describing: type(of: error))
            print("AI CHECK FAILED: " + reason); exit(1)
        }
    }
}
