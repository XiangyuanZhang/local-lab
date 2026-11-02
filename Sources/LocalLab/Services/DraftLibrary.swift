import Foundation

struct DraftLibrary {
    private let url: URL
    init(root: URL? = nil) {
        let folder = root ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("LocalLab", isDirectory: true)
        url = folder.appendingPathComponent("drafts.json")
    }
    func load() -> [ScriptDraft] {
        guard let data = try? Data(contentsOf: url), let drafts = try? JSONDecoder().decode([ScriptDraft].self, from: data), !drafts.isEmpty else { return ScriptDraft.initial }
        return drafts
    }
    func save(_ drafts: [ScriptDraft]) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try JSONEncoder().encode(drafts).write(to: url, options: .atomic)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
    }
}
