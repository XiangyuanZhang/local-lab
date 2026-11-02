import Foundation

/// Separate from Jupyter credentials. No Keychain prompts, UserDefaults or bundled API keys.
final class AIReviewRepository {
    let directory: URL
    private var configurationURL: URL { directory.appendingPathComponent("settings.json") }
    private var credentialsURL: URL { directory.appendingPathComponent("api-keys.json") }
    init(directory: URL = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("LocalLab/AIReview")) {
        self.directory = directory
    }
    func load() throws -> AIReviewConfiguration {
        guard FileManager.default.fileExists(atPath: configurationURL.path) else { return AIReviewConfiguration() }
        do {
            let data = try Data(contentsOf: configurationURL)
            guard data.count <= 524_288 else { throw AIReviewError.storage }
            return try JSONDecoder().decode(AIReviewConfiguration.self, from: data).validated()
        } catch { throw AIReviewError.storage }
    }
    func save(_ value: AIReviewConfiguration) throws {
        let valid = try value.validated()
        do { try write(JSONEncoder().encode(valid), to: configurationURL) }
        catch { throw AIReviewError.storage }
    }
    func key(for endpoint: String) throws -> String? {
        let scope = try AIEndpoint(endpoint).scope
        return try keys()[scope]
    }
    func saveKey(_ value: String, for endpoint: String) throws {
        let key = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !key.isEmpty, key.utf8.count <= 4096,
              !key.unicodeScalars.contains(where: CharacterSet.controlCharacters.contains) else { throw AIReviewError.invalidKey }
        let scope = try AIEndpoint(endpoint).scope
        var stored = try keys(); stored[scope] = key
        do { try write(JSONEncoder().encode(stored), to: credentialsURL) }
        catch { throw AIReviewError.storage }
    }
    func removeKey(for endpoint: String) throws {
        let scope = try AIEndpoint(endpoint).scope
        var stored = try keys(); stored[scope] = nil
        do { try write(JSONEncoder().encode(stored), to: credentialsURL) }
        catch { throw AIReviewError.storage }
    }
    private func keys() throws -> [String: String] {
        guard FileManager.default.fileExists(atPath: credentialsURL.path) else { return [:] }
        do {
            let data = try Data(contentsOf: credentialsURL)
            guard data.count <= 262_144 else { throw AIReviewError.storage }
            return try JSONDecoder().decode([String: String].self, from: data)
        } catch { throw AIReviewError.storage }
    }
    private func write(_ data: Data, to url: URL) throws {
        // The private directory also protects the temporary file used by atomic writes.
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: directory.path)
        try data.write(to: url, options: .atomic)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
    }
}
