import Foundation

/// A token shipped inside the app bundle so a personal build can connect
/// without going through the login keychain.
///
/// The value comes from `Resources/builtin-token.txt`, which the build script
/// copies into `Contents/Resources`. That file is git-ignored, so the token
/// never lands in the repository; a missing or empty file simply disables the
/// feature and falls back to the stored credential.
enum BuiltinCredential {
    static let token: String? = read()
    static var isAvailable: Bool { token != nil }

    private static func read() -> String? {
        // Only the copy inside the bundle counts; the source tree happens to contain
        // the same file, and the test harness must not pick it up.
        guard let resources = Bundle.main.resourceURL else { return nil }
        let candidates = [resources.appendingPathComponent("builtin-token.txt")]
        for url in candidates {
            guard let text = try? String(contentsOf: url, encoding: .utf8) else { continue }
            let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty { return trimmed }
        }
        return nil
    }
}
