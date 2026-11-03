import Foundation

/// Passive rendering only. Notebook code and rich HTML output are never executed.
enum NotebookMarkdown {
    static func render(_ json: String) throws -> String {
        guard json.utf8.count <= 8_388_608,
              let root = try JSONSerialization.jsonObject(with: Data(json.utf8)) as? [String: Any],
              root["nbformat"] as? Int == 4, let cells = root["cells"] as? [[String: Any]], cells.count <= 2000 else {
            throw LabError.message("Notebook 格式不支援或超過預覽限制（nbformat 4，最多 8 MB／2000 個單元格）。")
        }
        func text(_ value: Any?) -> String {
            if let value = value as? String { return value }
            return (value as? [String])?.joined() ?? ""
        }
        func block(_ value: String, language: String = "") -> String {
            let longest = value.split(whereSeparator: { $0 != "`" }).map(\.count).max() ?? 0
            let fence = String(repeating: "`", count: max(3, longest + 1))
            return "\n\(fence)\(language)\n\(value)\n\(fence)\n"
        }
        var result: [String] = []
        for (index, cell) in cells.enumerated() {
            let source = text(cell["source"])
            switch cell["cell_type"] as? String {
            case "markdown": result.append(source)
            case "code":
                result.append("### 程式碼單元格 \(index + 1)\n" + block(source, language: "python"))
                for output in cell["outputs"] as? [[String: Any]] ?? [] {
                    if output["output_type"] as? String == "stream" { result.append(block(text(output["text"]))) }
                    else if output["output_type"] as? String == "error" {
                        let trace = (output["traceback"] as? [String])?.joined(separator: "\n") ?? text(output["traceback"])
                        let error = trace.replacingOccurrences(of: "\u{001B}\\[[0-?]*[ -/]*[@-~]", with: "", options: .regularExpression)
                        result.append(block(error.isEmpty ? text(output["ename"]) + ": " + text(output["evalue"]) : error))
                    } else if let data = output["data"] as? [String: Any] {
                        let plain = text(data["text/plain"])
                        if !plain.isEmpty { result.append(block(plain)) }
                        let png = text(data["image/png"]).filter { !$0.isWhitespace }
                        if png.count <= 7_000_000, let image = Data(base64Encoded: png), validPNG(image) {
                            result.append("![Notebook 輸出圖片](data:image/png;base64,\(png))")
                        }
                    }
                }
            default: result.append(block(source))
            }
        }
        let rendered = result.joined(separator: "\n\n")
        guard rendered.utf8.count <= 12_582_912 else { throw LabError.message("Notebook 預覽內容過大。") }
        return rendered
    }
    private static func validPNG(_ data: Data) -> Bool {
        guard data.count >= 24, data.starts(with: [137,80,78,71,13,10,26,10]),
              Array(data[12..<16]) == [73,72,68,82] else { return false }
        let width = data[16..<20].reduce(UInt64(0)) { ($0 << 8) | UInt64($1) }
        let height = data[20..<24].reduce(UInt64(0)) { ($0 << 8) | UInt64($1) }
        return (1...8192).contains(width) && (1...8192).contains(height) && width * height <= 16_777_216
    }

}
