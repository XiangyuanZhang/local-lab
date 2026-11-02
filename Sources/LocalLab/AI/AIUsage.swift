import Foundation

struct AIUsage: Decodable, Equatable, Sendable {
    let prompt_tokens: Int
    let completion_tokens: Int
    let total_tokens: Int
    var isValid: Bool {
        (0...1_000_000_000).contains(prompt_tokens) && (0...1_000_000_000).contains(completion_tokens)
        && total_tokens == prompt_tokens + completion_tokens
    }
}

struct AIRequestMetrics: Equatable, Sendable {
    var usage: AIUsage?
    var model: String?
    var elapsed: TimeInterval?
    var tokensPerSecond: Double? {
        guard let usage, usage.isValid, let elapsed, elapsed.isFinite, elapsed > 0 else { return nil }
        return Double(usage.total_tokens) / elapsed
    }
    static func decode(_ data: Data) -> Self {
        struct Metadata: Decodable { let model: String?; let usage: AIUsage? }
        // Bad optional telemetry must never invalidate an otherwise valid code review.
        guard let value = try? JSONDecoder().decode(Metadata.self, from: data) else { return Self() }
        let model = value.model.flatMap { !$0.isEmpty && $0.utf8.count <= 128 && !$0.unicodeScalars.contains(where: CharacterSet.controlCharacters.contains) ? $0 : nil }
        return Self(usage: value.usage.flatMap { $0.isValid ? $0 : nil }, model: model)
    }
}

struct AIMeasuredFailure: Error, Sendable {
    let error: AIReviewError
    let metrics: AIRequestMetrics
}

struct AIUsageSession: Equatable {
    private(set) var last: AIRequestMetrics?
    private(set) var totalTokens: Int64 = 0
    private(set) var unknownRequests = 0
    mutating func record(_ metrics: AIRequestMetrics) {
        last = metrics
        if let usage = metrics.usage, usage.isValid {
            let (sum, overflow) = totalTokens.addingReportingOverflow(Int64(usage.total_tokens))
            if overflow { unknownRequests += 1 } else { totalTokens = sum }
        } else { unknownRequests += 1 }
    }
    static func number(_ value: Int64) -> String {
        value.formatted(.number.locale(Locale(identifier: "en_US_POSIX")))
    }
    var lastText: String { last?.usage.map { Self.number(Int64($0.total_tokens)) } ?? "—" }
    var totalText: String { (unknownRequests > 0 ? "≥" : "") + Self.number(totalTokens) }
    var speedText: String {
        guard let speed = last?.tokensPerSecond else { return "— tok/s" }
        return speed.formatted(.number.precision(.fractionLength(1)).locale(Locale(identifier: "en_US_POSIX"))) + " tok/s"
    }
}
