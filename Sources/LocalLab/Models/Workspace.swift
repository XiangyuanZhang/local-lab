import Foundation

struct ScriptDraft: Identifiable, Codable, Equatable {
    var id = UUID()
    var name: String
    var code: String
    var remotePath: String? = nil
    var remoteModified: String? = nil
    var remoteBaseContent: String? = nil
    var isRemoteDirty: Bool { remotePath != nil && code != remoteBaseContent }
    static let initial = [
        ScriptDraft(name: "hello.py", code: "# 在 TUM 的 Python 核心執行\nprint('Hello from local API')\n\nvalues = [2, 4, 6, 8]\nprint('Total:', sum(values))\n"),
        ScriptDraft(name: "experiment.py", code: "# 在這裡開始你的實驗\nimport math\n\nfor n in range(1, 6):\n    print(f'{n}: {math.sqrt(n):.3f}')\n")
    ]
}

struct KernelInfo: Codable, Sendable { var id: String; var name: String }
struct ConnectionInfo: Sendable { var kernel: KernelInfo; var existingCount: Int; var displayName: String; var pythonVersion: String? = nil }
enum KernelEvent: Sendable {
    case text(String, isError: Bool)
    case image(Data)
    case clear
    case completed(success: Bool)
}
struct OutputItem: Identifiable {
    let id = UUID()
    var text: String?
    var image: Data?
    var isError = false
}

enum LabError: LocalizedError {
    case message(String)
    var errorDescription: String? { if case .message(let value) = self { return value }; return nil }
    static func http(_ status: Int) -> LabError {
        switch status {
        case 401, 403: return .message("授權失敗。請檢查 token 是否到期，以及 scope 是否為 access:servers!server=go97lep/。")
        case 404: return .message("找不到遠端核心或 API。請確認 JupyterLab 伺服器仍在執行。")
        default: return .message("遠端服務回傳 HTTP \(status)。請稍後重試。")
        }
    }
}

protocol KernelService: AnyObject {
    func connect(token: String) async throws -> ConnectionInfo
    func execute(code: String, onEvent: @escaping @Sendable (KernelEvent) async -> Void) async throws
    func interrupt() async throws
    func disconnect() async throws
    func ownedKernelID() async -> String?
}

enum BottomPanel: String, CaseIterable, Identifiable {
    case output = "執行結果", local = "本機 Terminal", remote = "伺服器 Terminal"
    var id: String { rawValue }
}
