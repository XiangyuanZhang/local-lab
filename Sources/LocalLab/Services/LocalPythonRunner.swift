import Foundation

struct ProcessResult: Sendable { let status: Int32; let stdout: String; let stderr: String }
final class ProcessControl: @unchecked Sendable {
    private let lock = NSLock()
    private var process: Process?
    private var cancelled = false
    func attach(_ value: Process) { lock.lock(); process = value; if cancelled && value.isRunning { value.terminate() }; lock.unlock() }
    func stop() { lock.lock(); cancelled = true; if let process, process.isRunning { process.terminate() }; lock.unlock() }
}
func capturedProcess(_ executable: URL, _ arguments: [String], directory: URL? = nil, control: ProcessControl = ProcessControl(), timeout: UInt64 = 120) async throws -> ProcessResult {
    try Task.checkCancellation()
    let process = Process(); process.executableURL = executable; process.arguments = arguments; process.currentDirectoryURL = directory
    let out = Pipe(), err = Pipe(); process.standardOutput = out; process.standardError = err
    process.standardInput = FileHandle.nullDevice
    var environment = ProcessInfo.processInfo.environment
    environment["PYTHONUNBUFFERED"] = "1"; environment["PYTHONDONTWRITEBYTECODE"] = "1"
    process.environment = environment
    return try await withTaskCancellationHandler {
        try process.run(); control.attach(process)
        func drain(_ file: FileHandle) -> Task<String, Never> {
            Task.detached {
                var data = Data()
                while let part = try? file.read(upToCount: 16384), !part.isEmpty {
                    if data.count < 1_048_576 { data.append(part.prefix(1_048_576 - data.count)) }
                }
                return String(decoding: data, as: UTF8.self)
            }
        }
        let stdout = drain(out.fileHandleForReading), stderr = drain(err.fileHandleForReading)
        let timer = Task { try? await Task.sleep(nanoseconds: timeout * 1_000_000_000); if !Task.isCancelled { control.stop() } }
        await Task.detached { process.waitUntilExit() }.value
        timer.cancel()
        let result = await ProcessResult(status: process.terminationStatus, stdout: stdout.value, stderr: stderr.value)
        try Task.checkCancellation(); return result
    } onCancel: { control.stop() }
}

protocol LocalPythonService: Sendable {
    func run(code: String, name: String, version: String, onText: @escaping @Sendable (String, Bool) async -> Void) async throws -> Bool
    func interrupt() async
}
actor LocalPythonRunner: LocalPythonService {
    private let root: URL
    private var control: ProcessControl?
    init(root: URL = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("LocalLab")) { self.root = root }
    func interrupt() { control?.stop() }
    func run(code: String, name: String, version: String, onText: @escaping @Sendable (String, Bool) async -> Void) async throws -> Bool {
        guard version.range(of: #"^\d+\.\d+\.\d+$"#, options: .regularExpression) != nil else { throw LabError.message("無法取得伺服器的完整 Python 版本，已停止執行。") }
        let python = try await prepare(version: version)
        let workspaceSetting = UserDefaults.standard.string(forKey: "localWorkspace") ?? ""
        let workspace = workspaceSetting.isEmpty ? root.appendingPathComponent("Workspace") : URL(fileURLWithPath: workspaceSetting)
        try FileManager.default.createDirectory(at: workspace, withIntermediateDirectories: true)
        let scratch = root.appendingPathComponent("Runs/" + UUID().uuidString)
        try FileManager.default.createDirectory(at: scratch, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        defer { try? FileManager.default.removeItem(at: scratch); control = nil }
        let script = scratch.appendingPathComponent(URL(fileURLWithPath: name).lastPathComponent)
        try Data(code.utf8).write(to: script)
        let active = ProcessControl(); control = active
        await onText("本機 · Python \(version)\n工作目錄：\(workspace.path)\n", false)
        // Compile with the draft name, so traceback and syntax errors show the same file and line as the editor.
        let wrapper = "import sys, pathlib\nsys.path.insert(0, str(pathlib.Path.cwd()))\nsource = pathlib.Path(sys.argv[1]).read_text(encoding='utf-8')\nexec(compile(source, sys.argv[2], 'exec'), {'__name__':'__main__', '__file__':sys.argv[2]})\n"
        let result = try await capturedProcess(python, ["-u", "-B", "-c", wrapper, script.path, name], directory: workspace, control: active)
        if !result.stdout.isEmpty { await onText(result.stdout, false) }
        if !result.stderr.isEmpty { await onText(result.stderr, true) }
        if result.status != 0 {
            await onText("\n本機執行失敗（結束碼 \(result.status)）；未送至伺服器。\n", true)
            return false
        }
        return true
    }
    private func prepare(version: String) async throws -> URL {
        let custom = UserDefaults.standard.string(forKey: "localPythonExecutable") ?? ""
        if !custom.isEmpty { return try await verify(URL(fileURLWithPath: custom), version: version) }
        let runtimeRoot = root.appendingPathComponent("Runtimes")
        try FileManager.default.createDirectory(at: runtimeRoot, withIntermediateDirectories: true)
        let runtime = runtimeRoot.appendingPathComponent("cpython-\(version)-macos-aarch64-none/bin/python3")
        if !FileManager.default.isExecutableFile(atPath: runtime.path) {
            if version == "3.10.12", let archive = Bundle.main.url(forResource: "python-3.10.12", withExtension: "tar.gz") {
                let unpack = try await capturedProcess(URL(fileURLWithPath: "/usr/bin/tar"), ["-xzf", archive.path, "-C", runtimeRoot.path])
                guard unpack.status == 0 else { throw LabError.message("本機 Python 解壓失敗：\(unpack.stderr)") }
            } else {
                let uvPaths = ["/opt/homebrew/bin/uv", "/usr/local/bin/uv"]
                guard let uv = uvPaths.first(where: { FileManager.default.isExecutableFile(atPath: $0) }) else { throw LabError.message("請在設定指定 Python \(version) 的執行檔；目前沒有相符的本機版本。") }
                let install = try await capturedProcess(URL(fileURLWithPath: uv), ["python", "install", version, "--install-dir", runtimeRoot.path, "--no-bin"])
                guard install.status == 0 else { throw LabError.message("準備 Python \(version) 失敗：\(install.stderr)") }
            }
        }
        _ = try await verify(runtime, version: version)
        let environment = root.appendingPathComponent("Environments/" + version)
        let python = environment.appendingPathComponent("bin/python3")
        if !FileManager.default.isExecutableFile(atPath: python.path) {
            let created = try await capturedProcess(runtime, ["-m", "venv", environment.path])
            guard created.status == 0 else { throw LabError.message("建立本機 Python 環境失敗：\(created.stderr)") }
        }
        return try await verify(python, version: version)
    }
    private func verify(_ executable: URL, version: String) async throws -> URL {
        guard FileManager.default.isExecutableFile(atPath: executable.path) else { throw LabError.message("找不到本機 Python 執行檔：\(executable.path)") }
        let result = try await capturedProcess(executable, ["-I", "-c", "import sys; print('.'.join(map(str, sys.version_info[:3])))"], timeout: 15)
        let actual = result.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
        guard result.status == 0, actual == version else { throw LabError.message("Python 版本不一致：本機 \(actual.isEmpty ? "無法辨識" : actual)，伺服器 \(version)。未執行程式，也未送至伺服器。") }
        return executable
    }
}
