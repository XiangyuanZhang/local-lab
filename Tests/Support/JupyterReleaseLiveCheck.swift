import Foundation
@main struct JupyterReleaseLiveCheck {
    static func main() async {
        guard CommandLine.arguments.count == 3, CommandLine.arguments[1] == "--live" else { exit(2) }
        let root = URL(fileURLWithPath: CommandLine.arguments[2])
        do {
            let file = URL(fileURLWithPath: "/Applications/Local Lab.app/Contents/Resources/builtin-token.txt")
            let token = try String(contentsOf: file, encoding: .utf8).trimmingCharacters(in: .whitespacesAndNewlines)
            let report = await AppLiveVerifier.run(credential: token, root: root)
            let object = try JSONSerialization.jsonObject(with: Data(contentsOf: report)) as? [String: Any]
            guard object?["success"] as? Bool == true else { exit(1) }
        } catch { print("Live verification could not finish; credentials are never logged."); exit(1) }
    }
}
