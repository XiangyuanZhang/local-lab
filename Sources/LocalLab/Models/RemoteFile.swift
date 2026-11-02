import Foundation
import CryptoKit

struct RemoteEntry: Codable, Identifiable, Sendable {
    let name: String
    let path: String
    let type: String
    let writable: Bool
    let lastModified: String
    let size: Int?
    var id: String { path }
    var selectionID: UUID {
        let bytes = Array(SHA256.hash(data: Data(("local-lab-remote:" + path).utf8)))
        return UUID(uuid: (bytes[0],bytes[1],bytes[2],bytes[3],bytes[4],bytes[5],bytes[6],bytes[7],bytes[8],bytes[9],bytes[10],bytes[11],bytes[12],bytes[13],bytes[14],bytes[15]))
    }
    var symbol: String { type == "directory" ? "folder" : type == "notebook" ? "book.closed" : "doc.text" }
    var kindLabel: String { type == "directory" ? "資料夾" : type == "notebook" ? "Notebook" : "檔案" }
    enum CodingKeys: String, CodingKey { case name, path, type, writable, size; case lastModified = "last_modified" }
}
struct RemoteTextFile: Sendable { let entry: RemoteEntry; let content: String }
struct RemoteFileMissing: Error, LocalizedError { let path: String; var errorDescription: String? { "遠端檔案已移除：\(path)" } }
struct RemoteConflict: Error, LocalizedError { let file: RemoteTextFile; var errorDescription: String? { "遠端檔案已修改，已保留本機內容。請處理版本衝突後再儲存。" } }
protocol RemoteFileService {
    func remoteDirectory(_ path: String) async throws -> [RemoteEntry]
    func remoteFile(_ path: String) async throws -> RemoteTextFile
    func saveRemoteFile(path: String, content: String, expectedContent: String) async throws -> RemoteTextFile
    func createRemoteFile(path: String, content: String) async throws -> RemoteTextFile
    func createRemoteDirectory(path: String) async throws
}
enum RemotePath {
    static func validated(_ path: String) throws -> String {
        guard !path.hasPrefix("/"), !path.contains("\\"), !path.contains("\0"), !path.split(separator: "/", omittingEmptySubsequences: false).contains(where: { $0 == ".." || $0 == "." }) else { throw LabError.message("請使用遠端主目錄內的相對路徑。") }
        return path
    }
    static func joined(_ folder: String, name: String) throws -> String {
        let name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty, !name.contains("/"), !name.contains("\\"), name != ".", name != ".." else { throw LabError.message("請輸入不含斜線的檔名。") }
        return try validated(folder.isEmpty ? name : folder + "/" + name)
    }
}
