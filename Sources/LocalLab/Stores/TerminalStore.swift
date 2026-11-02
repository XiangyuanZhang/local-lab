import Foundation

enum TerminalLocation: String, CaseIterable, Identifiable { case local = "本機 Terminal", remote = "伺服器 Terminal"; var id: String { rawValue } }
extension WorkspaceStore {
    func openTerminal(_ location: TerminalLocation) async {
        guard !terminalBusy.contains(location), terminals[location] == nil else { return }
        terminalBusy.insert(location); defer { terminalBusy.remove(location) }
        do {
            let terminal: ShellTerminal
            if location == .local { terminal = LocalShellTerminal(pythonVersion: connection?.pythonVersion) }
            else {
                guard isReady, let client = service as? JupyterClient else { throw LabError.message("請先連線至伺服器。") }
                terminal = try await client.shellTerminal()
            }
            do { try await terminal.start { [weak self] text in await self?.appendTerminal(text, location: location) } }
            catch { try? await terminal.stop(); throw error }
            terminals[location] = terminal; terminalStates[location] = "已連線"
        } catch { terminalStates[location] = "連線失敗"; appendTerminal(safeError(error) + "\n", location: location) }
    }
    func appendTerminal(_ text: String, location: TerminalLocation) {
        let clean = text.replacingOccurrences(of: #"\x1B\[[0-?]*[ -/]*[@-~]"#, with: "", options: .regularExpression)
            .replacingOccurrences(of: #"\x1B\][^\x07]*(?:\x07|\x1B\\)"#, with: "", options: .regularExpression)
            .replacingOccurrences(of: "\r", with: "")
        terminalOutput[location] = String(((terminalOutput[location] ?? "") + clean).suffix(262144))
    }
    func sendTerminal(_ text: String, location: TerminalLocation, newline: Bool = true) async {
        guard let terminal = terminals[location] else { return }
        do { try await terminal.send(text + (newline ? (location == .remote ? "\r" : "\n") : "")) }
        catch { appendTerminal(safeError(error) + "\n", location: location); terminalStates[location] = "連線中斷" }
    }
    func reconnectTerminal(_ location: TerminalLocation) async {
        guard !terminalBusy.contains(location) else { return }
        do { try await terminals[location]?.stop(); terminals[location] = nil; await openTerminal(location) }
        catch { appendTerminal(safeError(error) + "\n", location: location) }
    }
    func closeTerminals() async throws {
        for location in TerminalLocation.allCases {
            try await terminals[location]?.stop(); terminals[location] = nil; terminalStates[location] = "已關閉"
        }
    }
}
