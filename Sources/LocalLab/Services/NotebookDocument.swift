import Foundation

/// Preserves notebook and cell metadata, attachments and unknown fields while editing sources.
struct NotebookDocument {
    private(set) var root: [String: Any]
    var cells: [[String: Any]] { root["cells"] as? [[String: Any]] ?? [] }
    init(_ json: String) throws {
        guard json.utf8.count <= 8_388_608,
              let object = try JSONSerialization.jsonObject(with: Data(json.utf8)) as? [String: Any],
              object["nbformat"] as? Int == 4, let cells = object["cells"] as? [[String: Any]], cells.count <= 2000,
              cells.allSatisfy({ ["code", "markdown", "raw"].contains($0["cell_type"] as? String ?? "") && ($0["source"] is String || $0["source"] is [String]) }) else {
            throw LabError.message("Notebook 格式不正確（需要 nbformat 4，最多 8 MB／2000 個單元格）。")
        }
        root = object
    }
    func source(at index: Int) -> String {
        guard cells.indices.contains(index) else { return "" }
        let value = cells[index]["source"]
        return value as? String ?? (value as? [String])?.joined() ?? ""
    }
    mutating func updateSource(at index: Int, text: String) {
        guard cells.indices.contains(index), source(at: index) != text else { return }
        var items = cells; items[index]["source"] = text
        if items[index]["cell_type"] as? String == "code" {
            items[index]["outputs"] = []; items[index]["execution_count"] = NSNull()
        }
        root["cells"] = items
    }
    mutating func append(kind: String) {
        guard cells.count < 2000, ["code", "markdown"].contains(kind) else { return }
        var item: [String: Any] = ["id": UUID().uuidString.lowercased(), "cell_type": kind, "metadata": [:], "source": ""]
        if kind == "code" { item["outputs"] = []; item["execution_count"] = NSNull() }
        root["cells"] = cells + [item]
    }
    mutating func remove(at index: Int) {
        guard cells.indices.contains(index) else { return }
        var items = cells; items.remove(at: index); root["cells"] = items
    }
    func serialized() throws -> String {
        let data = try JSONSerialization.data(withJSONObject: root, options: [.sortedKeys])
        guard data.count <= 8_388_608 else { throw LabError.message("Notebook 超過 8 MB。") }
        return String(decoding: data, as: UTF8.self)
    }
    static let empty = "{\"nbformat\":4,\"nbformat_minor\":5,\"metadata\":{\"language_info\":{\"name\":\"python\"}},\"cells\":[]}"
    /// Jupyter may add defaults and convert string sources to arrays. Every submitted field must survive.
    func matchesSaved(_ json: String) throws -> Bool {
        let other = try NotebookDocument(json)
        func normalized(_ document: NotebookDocument) -> [String: Any] {
            var value = document.root
            value["cells"] = document.cells.indices.map { index -> [String: Any] in
                var cell = document.cells[index]; cell["source"] = document.source(at: index); return cell
            }
            return value
        }
        func includes(_ actual: Any, expected: Any) -> Bool {
            if let object = expected as? [String: Any] {
                guard let value = actual as? [String: Any] else { return false }
                return object.allSatisfy { key, item in value[key].map { includes($0, expected: item) } ?? false }
            }
            if let items = expected as? [Any] {
                guard let value = actual as? [Any], items.count == value.count else { return false }
                return zip(value, items).allSatisfy { includes($0.0, expected: $0.1) }
            }
            return (actual as? NSObject)?.isEqual(expected) == true
        }
        return includes(normalized(other), expected: normalized(self))
    }
    mutating func setOutputs(at index: Int, outputs: [[String: Any]], executionCount: Int? = nil) {
        guard cells.indices.contains(index), cells[index]["cell_type"] as? String == "code" else { return }
        var items = cells; items[index]["outputs"] = outputs; items[index]["execution_count"] = executionCount.map { $0 as Any } ?? NSNull(); root["cells"] = items
    }
    mutating func clearOutputs() {
        for index in cells.indices where cells[index]["cell_type"] as? String == "code" { setOutputs(at: index, outputs: []) }
    }
    func pythonCells(through last: Int? = nil) throws -> [(index: Int, code: String)] {
        _ = try pythonCode(through: last)
        return cells.indices.filter { ($0 <= (last ?? Int.max)) && cells[$0]["cell_type"] as? String == "code" && !source(at: $0).trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }.map { ($0, source(at: $0)) }
    }
    func pythonCode(through last: Int? = nil) throws -> String {
        let metadata = root["metadata"] as? [String: Any] ?? [:]
        let language = (metadata["language_info"] as? [String: Any])?["name"] as? String
        let kernelLanguage = (metadata["kernelspec"] as? [String: Any])?["language"] as? String
        if let language = language ?? kernelLanguage, !language.lowercased().hasPrefix("python") {
            throw LabError.message("目前只能執行 Python Notebook。")
        }
        let code = cells.indices.filter { ($0 <= (last ?? Int.max)) && cells[$0]["cell_type"] as? String == "code" }.map { source(at: $0) }.joined(separator: "\n\n")
        guard !code.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { throw LabError.message("Notebook 沒有可執行的程式碼。") }
        return code
    }
}

/// Bounded per-cell server output, kept separately from the combined local/remote console.
actor NotebookRunOutput {
    private var items: [[String: Any]] = []
    private var bytes = 0
    private var success = false
    private var count: Int?
    func append(_ event: KernelEvent) {
        switch event {
        case .executionCount(let value): count = value
        case .clear: items = []; bytes = 0; count = nil; success = false
        case .completed(let ok): success = ok
        case .text(let text, let error):
            guard bytes + text.utf8.count <= 1_048_576, items.count < 100 else { return }
            bytes += text.utf8.count
            items.append(["output_type": "stream", "name": error ? "stderr" : "stdout", "text": text])
        case .image(let data):
            guard bytes + data.count <= 2_097_152, items.count < 100 else { return }
            bytes += data.count
            items.append(["output_type": "display_data", "metadata": [:], "data": ["image/png": data.base64EncodedString()]])
        }
    }
    func result() -> (outputs: [[String: Any]], success: Bool, count: Int?) { (items, success, count) }
}
