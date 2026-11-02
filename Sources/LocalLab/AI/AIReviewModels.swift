import Foundation
import CryptoKit

enum AIReviewMode: String, Codable, CaseIterable, Identifiable, Sendable {
    case reviewOnly, edit
    var id: String { rawValue }
    var title: String { self == .reviewOnly ? "僅審碼" : "審碼並修改" }
    var actionTitle: String { self == .reviewOnly ? "開始審碼" : "生成修改" }
}

struct AIReviewPersona: Identifiable, Codable, Equatable, Sendable {
    var id: UUID
    var name: String
    var instructions: String
    static let defaults: [AIReviewPersona] = [
        .init(id: UUID(uuidString: "A1000000-0000-0000-0000-000000000001")!, name: "嚴謹審閱者", instructions: "用繁體中文簡潔回答。優先找出可重現的錯誤、邊界條件、資源問題與安全問題；區分確定的問題與推測，附上原因及具體修正建議。避免無意義的風格修改。"),
        .init(id: UUID(uuidString: "A1000000-0000-0000-0000-000000000002")!, name: "耐心導師", instructions: "用繁體中文協助學習程式設計。解釋問題發生的原因，提供小而清楚的例子，避免直接大幅重寫；保留學習者的思路。"),
        .init(id: UUID(uuidString: "A1000000-0000-0000-0000-000000000003")!, name: "最小修改工程師", instructions: "用繁體中文回答。只修改必要部分，保留既有 API、命名、介面與動效規範。不引入未要求的相依套件或額外功能；說明需要驗證的測試。")
    ]
}

struct AIReviewConfiguration: Codable, Equatable, Sendable {
    var baseURL = "https://api.deepseek.com"
    var model = "deepseek-flash"
    var mode: AIReviewMode = .reviewOnly
    var personas = AIReviewPersona.defaults
    var selectedPersonaID = AIReviewPersona.defaults[0].id
    var selectedPersona: AIReviewPersona { personas.first { $0.id == selectedPersonaID } ?? personas[0] }

    func validated() throws -> AIReviewConfiguration {
        var copy = self
        copy.baseURL = try AIEndpoint(baseURL).base.absoluteString
        copy.model = model.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !copy.model.isEmpty, copy.model.utf8.count <= 128,
              !copy.model.unicodeScalars.contains(where: CharacterSet.controlCharacters.contains),
              (1...20).contains(personas.count), Set(personas.map(\.id)).count == personas.count,
              personas.contains(where: { $0.id == selectedPersonaID }) else { throw AIReviewError.invalidSettings }
        copy.personas = try personas.map { persona in
            var p = persona; p.name = p.name.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !p.name.isEmpty, p.name.count <= 40,
                  !p.instructions.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                  p.instructions.utf8.count <= 16_384 else { throw AIReviewError.invalidPersona }
            return p
        }
        return copy
    }
}

struct AIEndpoint: Sendable {
    let base: URL
    let completions: URL
    let scope: String
    init(_ input: String) throws {
        guard var parts = URLComponents(string: input.trimmingCharacters(in: .whitespacesAndNewlines)),
              let scheme = parts.scheme?.lowercased(), let host = parts.host?.lowercased(), !host.isEmpty,
              parts.user == nil, parts.password == nil, parts.query == nil, parts.fragment == nil,
              scheme == "https" || (scheme == "http" && ["localhost", "127.0.0.1", "::1", "[::1]"].contains(host)) else { throw AIReviewError.invalidEndpoint }
        parts.scheme = scheme; parts.host = host
        while parts.path.hasSuffix("/") { parts.path.removeLast() }
        if parts.path.hasSuffix("/chat/completions") { parts.path.removeLast("/chat/completions".count) }
        guard let url = parts.url, url.absoluteString.utf8.count <= 2048 else { throw AIReviewError.invalidEndpoint }
        base = url; completions = url.appendingPathComponent("chat/completions")
        scope = SHA256.hash(data: Data(url.absoluteString.utf8)).map { String(format: "%02x", $0) }.joined()
    }
}

struct AIReviewSnapshot: Equatable, Sendable {
    let draftID: UUID
    let filename: String
    let remotePath: String?
    let code: String
    init(_ draft: ScriptDraft) { draftID = draft.id; filename = draft.name; remotePath = draft.remotePath; code = draft.code }
    func matches(_ draft: ScriptDraft?) -> Bool {
        guard let draft else { return false }
        return draft.id == draftID && draft.name == filename && draft.remotePath == remotePath && draft.code == code
    }
}

struct AIReviewRequest: Sendable {
    let snapshot: AIReviewSnapshot
    let persona: AIReviewPersona
    let mode: AIReviewMode
    let instruction: String
}

struct AIReviewFinding: Codable, Identifiable, Equatable, Sendable {
    enum Severity: String, Codable, Sendable { case high, medium, low, info
        var title: String { switch self { case .high: "高"; case .medium: "中"; case .low: "低"; case .info: "建議" } }
    }
    var severity: Severity
    var line: Int?
    var title: String
    var detail: String
    var id: String { "\(severity.rawValue):\(line ?? 0):\(title):\(detail)" }
}

struct AIReviewResponse: Equatable, Sendable {
    let summary: String
    let findings: [AIReviewFinding]
    let replacementCode: String?
}

struct AIReviewResult: Identifiable, Sendable {
    let id = UUID()
    let request: AIReviewRequest
    let response: AIReviewResponse
    let model: String
    let provider: String
    let date = Date()
    var proposedCode: String? { request.mode == .edit ? response.replacementCode : nil }
    var hasChanges: Bool { proposedCode.map { $0 != request.snapshot.code } ?? false }
}

struct AIReviewDiffLine: Identifiable {
    enum Kind { case context, removed, added }
    let id: Int
    let text: String
    let kind: Kind
}

/// A bounded contiguous changed-block preview; never builds an O(n²) LCS table.
struct AIReviewDiff {
    let lines: [AIReviewDiffLine]
    let omitted: Int
    init(before: String, after: String) {
        let a = before.components(separatedBy: "\n"), b = after.components(separatedBy: "\n")
        var prefix = 0, suffix = 0
        while prefix < min(a.count, b.count), a[prefix] == b[prefix] { prefix += 1 }
        while suffix < min(a.count, b.count) - prefix, a[a.count - 1 - suffix] == b[b.count - 1 - suffix] { suffix += 1 }
        var rows: [(String, AIReviewDiffLine.Kind)] = []
        for i in max(0, prefix - 3)..<prefix { rows.append((a[i], .context)) }
        for i in prefix..<(a.count - suffix) { rows.append((a[i], .removed)) }
        for i in prefix..<(b.count - suffix) { rows.append((b[i], .added)) }
        for i in (a.count - suffix)..<min(a.count, a.count - suffix + 3) { rows.append((a[i], .context)) }
        omitted = max(0, rows.count - 500)
        lines = rows.prefix(500).enumerated().map { .init(id: $0.offset, text: $0.element.0, kind: $0.element.1) }
    }
}

enum AIReviewError: Error, LocalizedError {
    case invalidEndpoint, invalidSettings, invalidPersona, missingKey, invalidKey, emptyCode, inputTooLarge
    case http(Int), network(Int), malformedResponse, incompleteResponse, responseTooLarge, documentChanged, documentBusy, noChanges, reviewOnly, storage
    var errorDescription: String? {
        switch self {
        case .invalidEndpoint: return "請輸入 HTTPS API 根網址（本機測試可使用 localhost HTTP）；不含帳密或查詢參數。"
        case .invalidSettings: return "請檢查模型名稱與人格選擇。"
        case .invalidPersona: return "人格需要名稱（最多 40 字）與提示詞（最多 16 KB）；至少保留一個人格。"
        case .missingKey: return "請先在 AI 設定中儲存此接口的 API Key。"
        case .invalidKey: return "API Key 不可含換行或控制字元。"
        case .emptyCode: return "請先開啟有內容的程式檔案。"
        case .inputTooLarge: return "單次程式碼上限 128 KB，補充要求上限 16 KB。請縮小內容後再試。"
        case .http(let status): return "AI API 回傳 HTTP \(status)。" + ([401,403].contains(status) ? "請檢查 API Key 與權限。" : status == 429 ? "請稍後再試，或檢查配額。" : "請檢查接口及模型設定後重試。")
        case .network(let code): return "AI 連線失敗（\(code)），請檢查網路後重試。"
        case .malformedResponse: return "AI 回應格式不完整，未生成可套用的修改。請重試。"
        case .incompleteResponse: return "AI 輸出被截斷或未正常完成，未生成可套用的修改。請縮小內容後重試。"
        case .responseTooLarge: return "AI 回應超出大小上限，未套用修改。"
        case .documentChanged: return "檔案已切換或內容已變更；請重新審碼，避免覆蓋你的修改。"
        case .documentBusy: return "檔案正在執行或同步，請稍後再套用。"
        case .noChanges: return "沒有可套用的修改。"
        case .reviewOnly: return "僅審碼模式不會更改程式碼。"
        case .storage: return "無法讀寫 AI 本機設定；請檢查檔案權限。"
        }
    }
}
