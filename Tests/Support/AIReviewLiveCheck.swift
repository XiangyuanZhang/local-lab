import Foundation

/// Explicit opt-in only. Sends this fixed, non-sensitive toy file, never workspace contents.
@main struct AIReviewLiveCheck {
    @MainActor static func main() async {
        guard CommandLine.arguments.contains("--live") else { print("Pass --live to make one paid provider request."); exit(2) }
        do {
            let repository = AIReviewRepository()
            var config = AIReviewConfiguration()
            config.mode = .reviewOnly
            guard let key = try repository.key(for: config.baseURL) else { throw AIReviewError.missingKey }
            let draft = ScriptDraft(name: "api-smoke.py", code: "def divide(a, b):\n    return a / b\n\nprint(divide(1, 0))\n")
            let request = AIReviewRequest(snapshot: AIReviewSnapshot(draft), persona: config.selectedPersona, mode: .reviewOnly, instruction: "請用中文簡短審查。")
            let response = try await AIReviewClient().review(request, configuration: config, key: key)
            guard let usage = response.metrics.usage, response.metrics.tokensPerSecond != nil, response.replacementCode == nil else { throw AIReviewError.malformedResponse }
            let output: [String: Any] = ["success": true, "provider": "DeepSeek", "model": response.metrics.model ?? config.model,
                                       "prompt_tokens": usage.prompt_tokens, "completion_tokens": usage.completion_tokens,
                                       "total_tokens": usage.total_tokens, "elapsed_seconds": response.metrics.elapsed ?? 0,
                                       "average_tokens_per_second": response.metrics.tokensPerSecond ?? 0,
                                       "findings": response.findings.count, "summary": response.summary]
            print(String(decoding: try JSONSerialization.data(withJSONObject: output, options: [.prettyPrinted, .sortedKeys]), as: UTF8.self))
        } catch {
            let safe = (error as? AIReviewError) ?? (error as? AIMeasuredFailure)?.error
            print("LIVE CHECK FAILED: " + (safe?.localizedDescription ?? "Unexpected response")); exit(1)
        }
    }
}
