import Foundation
import Darwin

/// One owned Python process keeps notebook variables alive without rerunning earlier cells.
final class LocalNotebookProcess: @unchecked Sendable {
    private let process = Process()
    private let input = Pipe(), output = Pipe()
    init(python: URL, directory: URL) throws {
        process.executableURL = python; process.arguments = ["-u", "-B", "-c", Self.worker]
        process.currentDirectoryURL = directory
        process.standardInput = input; process.standardOutput = output; process.standardError = FileHandle.nullDevice
        var environment = ProcessInfo.processInfo.environment
        environment["PYTHONDONTWRITEBYTECODE"] = "1"; environment["MPLBACKEND"] = "Agg"
        process.environment = environment
        try process.run()
    }
    deinit { stop() }
    var isRunning: Bool { process.isRunning }
    func stop() { if process.isRunning { kill(process.processIdentifier, SIGKILL) } }
    func execute(code: String, name: String) async throws -> ProcessResult {
        let data = try JSONSerialization.data(withJSONObject: ["code": code, "name": name]) + Data([10])
        let timer = Task { [weak self] in
            do { try await Task.sleep(nanoseconds: 120_000_000_000) } catch { return }
            self?.stop()
        }
        defer { timer.cancel() }
        return try await withTaskCancellationHandler {
            let result = try await Task.detached { [self] in
                try input.fileHandleForWriting.write(contentsOf: data)
                var response = Data()
                while response.count <= 8_388_608 {
                    var buffer = [UInt8](repeating: 0, count: 65536)
                    let length = Darwin.read(output.fileHandleForReading.fileDescriptor, &buffer, buffer.count)
                    guard length > 0 else { throw LabError.message("Local notebook kernel stopped. Re-run the required definition cells.") }
                    response.append(contentsOf: buffer.prefix(length))
                    if response.last == 10 { break }
                }
                guard response.count <= 8_388_608, let object = try JSONSerialization.jsonObject(with: response) as? [String: Any], let ok = object["ok"] as? Bool else {
                    stop(); throw LabError.message("Local notebook kernel returned an invalid response.")
                }
                return ProcessResult(status: ok ? 0 : 1, stdout: object["stdout"] as? String ?? "", stderr: object["stderr"] as? String ?? "")
            }.value
            try Task.checkCancellation(); return result
        } onCancel: { self.stop() }
    }
    private static let worker = #"""
import sys, json, io, ast, traceback, contextlib
protocol_in, protocol_out = sys.stdin, sys.stdout
namespace = {'__name__': '__main__'}
class LimitedText(io.StringIO):
    def write(self, text):
        remaining = max(0, 524288 - self.tell())
        if remaining: super().write(text[:remaining])
        return len(text)
for line in protocol_in:
    out, err, ok = LimitedText(), LimitedText(), True
    try:
        request = json.loads(line)
        name = request['name']
        namespace['__file__'] = name
        with contextlib.redirect_stdout(out), contextlib.redirect_stderr(err):
            old_stdin = sys.stdin
            sys.stdin = io.StringIO('')
            try:
                tree = ast.parse(request['code'], filename=name, mode='exec')
                last = tree.body.pop() if tree.body and isinstance(tree.body[-1], ast.Expr) else None
                exec(compile(tree, name, 'exec'), namespace)
                if last is not None:
                    value = eval(compile(ast.Expression(last.value), name, 'eval'), namespace)
                    if value is not None: print(repr(value))
            finally: sys.stdin = old_stdin
    except BaseException:
        ok = False
        traceback.print_exc(file=err)
    protocol_out.write(json.dumps({'ok': ok, 'stdout': out.getvalue(), 'stderr': err.getvalue()}, ensure_ascii=False) + '\n')
    protocol_out.flush()
"""#
}
