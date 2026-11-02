import Foundation
import Security

protocol TokenVault {
    func read() throws -> String?
    func save(_ token: String) throws
    func remove() throws
    func repairAccess() throws -> String?
}
extension TokenVault { func repairAccess() throws -> String? { try read() } }
struct KeychainTokenVault: TokenVault {
    let service: String
    let account: String
    private static let interactionLock = NSLock()
    init(service: String = "local.edward.LocalLab", account: String = "go97lep@lecture.cs.tum.de:9000") { self.service = service; self.account = account }
    private var query: [String: Any] { [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service, kSecAttrAccount as String: account, kSecAttrSynchronizable as String: false] }
    // File-based keychains ignore some SecItem authentication-UI options. Scope the
    // legacy setting to this process and restore it before returning.
    private func withInteraction<T>(_ allowed: Bool, _ operation: () throws -> T) throws -> T {
        Self.interactionLock.lock(); defer { Self.interactionLock.unlock() }
        var previous = DarwinBoolean(true)
        let status = SecKeychainGetUserInteractionAllowed(&previous)
        guard status == errSecSuccess else { throw failure(status) }
        let changed = SecKeychainSetUserInteractionAllowed(allowed)
        guard changed == errSecSuccess else { throw failure(changed) }
        defer { SecKeychainSetUserInteractionAllowed(previous.boolValue) }
        return try operation()
    }
    func read() throws -> String? { try withInteraction(false) { try readItem() } }
    private func readItem() throws -> String? {
        var request = query
        request[kSecReturnData as String] = true; request[kSecMatchLimit as String] = kSecMatchLimitOne
        var value: CFTypeRef?
        let status = SecItemCopyMatching(request as CFDictionary, &value)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess, let data = value as? Data, let token = String(data: data, encoding: .utf8) else { throw failure(status) }
        return token
    }
    private func appAccess() throws -> SecAccess {
        var trusted: SecTrustedApplication?
        let status = Bundle.main.bundleURL.path.withCString { SecTrustedApplicationCreateFromPath($0, &trusted) }
        guard status == errSecSuccess, let trusted else { throw failure(status) }
        var access: SecAccess?
        let created = SecAccessCreate("Local Lab — TUM API token" as CFString, [trusted] as CFArray, &access)
        guard created == errSecSuccess, let access else { throw failure(created) }
        return access
    }
    func repairAccess() throws -> String? {
        try withInteraction(true) {
            // Only the exact token item is changed. Its trusted app is the signed
            // Local Lab bundle; no all-app ACL or global trust is added.
            guard let token = try readItem() else { return nil }
            let status = SecItemUpdate(query as CFDictionary, [kSecAttrAccess as String: try appAccess()] as CFDictionary)
            guard status == errSecSuccess else { throw failure(status) }
            return token
        }
    }
    func save(_ token: String) throws {
        try withInteraction(true) {
            let data = Data(token.utf8)
            let status = SecItemUpdate(query as CFDictionary, [kSecValueData as String: data] as CFDictionary)
            if status == errSecItemNotFound {
                var item = query
                item[kSecValueData as String] = data
                item[kSecAttrLabel as String] = "Local Lab — TUM API token"
                item[kSecAttrAccess as String] = try appAccess()
                let added = SecItemAdd(item as CFDictionary, nil)
                guard added == errSecSuccess else { throw failure(added) }
            } else if status != errSecSuccess { throw failure(status) }
        }
    }
    func remove() throws {
        try withInteraction(true) {
            let status = SecItemDelete(query as CFDictionary)
            guard status == errSecSuccess || status == errSecItemNotFound else { throw failure(status) }
        }
    }
    private func failure(_ status: OSStatus) -> LabError { .message("Keychain OSStatus \(status)" + (status == errSecInteractionNotAllowed ? " · 請使用「修復鑰匙圈授權」一次。" : "")) }
}

/// Stores the API token in a 0600 file inside Application Support instead of the
/// login keychain. This keeps personal builds working without any keychain ACLs:
/// the ad-hoc signature changes on every rebuild, which is what made the legacy
/// keychain item unreadable.
struct FileTokenVault: TokenVault {
    let url: URL
    init(url: URL? = nil) {
        self.url = url ?? FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("LocalLab/credential.txt")
    }
    func read() throws -> String? {
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        let text = try String(contentsOf: url, encoding: .utf8).trimmingCharacters(in: .whitespacesAndNewlines)
        return text.isEmpty ? nil : text
    }
    func save(_ token: String) throws {
        let directory = url.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let text = token.trimmingCharacters(in: .whitespacesAndNewlines)
        try text.write(to: url, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
    }
    func remove() throws {
        guard FileManager.default.fileExists(atPath: url.path) else { return }
        try FileManager.default.removeItem(at: url)
    }
    func repairAccess() throws -> String? { try read() }
}
