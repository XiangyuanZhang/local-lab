import Foundation

@MainActor extension WorkspaceStore {
    var isNotebookSelected: Bool { selected?.name.lowercased().hasSuffix(".ipynb") == true }
    var canExecuteNotebookCode: Bool { isReady && !busy && runningID == nil }
    func selectNotebookCell(_ index: Int, editing: Bool = false) {
        guard let draft = selected, let document = try? NotebookDocument(draft.code), document.cells.indices.contains(index) else { return }
        notebookSelection[draft.id] = index
        if editing { notebookEditing[draft.id] = index }
        if document.cells[index]["cell_type"] as? String == "code", !document.source(at: index).trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { notebookRecentCode[draft.id] = index }
    }
    var reviewNotebookCellIndex: Int? {
        guard let draft = selected, let doc = try? NotebookDocument(draft.code) else { return nil }
        let index = notebookRecentCode[draft.id] ?? notebookSelection[draft.id]
        if let index, doc.cells.indices.contains(index), doc.cells[index]["cell_type"] as? String == "code" { return index }
        if let index = notebookRecentCode[draft.id], doc.cells.indices.contains(index), doc.cells[index]["cell_type"] as? String == "code" { return index }
        return nil
    }
    func runCurrentNotebookCell(advance: Bool = false) {
        guard let draft = selected, let document = try? NotebookDocument(draft.code), !document.cells.isEmpty else { return }
        let index = max(0, min(notebookSelection[draft.id] ?? 0, document.cells.count - 1))
        notebookEditing[draft.id] = nil
        if document.cells[index]["cell_type"] as? String != "code" {
            if advance { advanceNotebookCell(after: index, draftID: draft.id) }
            return
        }
        runNotebook(cell: index, advance: advance)
    }
    func runAllNotebook() { runNotebook() }
    func advanceNotebookCell(after index: Int, draftID: UUID) {
        guard selected?.id == draftID, let draft = selected, var doc = try? NotebookDocument(draft.code) else { return }
        if index + 1 >= doc.cells.count { doc.append(kind: "code"); if let value = try? doc.serialized() { updateCode(value) } }
        selectNotebookCell(min(index + 1, doc.cells.count - 1))
    }
    func runNotebook(cell: Int? = nil, through: Int? = nil, advance: Bool = false) {
        guard canExecuteNotebookCode, let draft = selected else { return }
        let cells: [(index: Int, code: String)]
        do {
            let doc = try NotebookDocument(draft.code)
            _ = try doc.pythonCode() // Validate the kernel language without executing any other cells.
            cells = try doc.pythonCells(through: through).filter { cell == nil || $0.index == cell }
            guard !cells.isEmpty else { return }
        } catch { self.error = error.localizedDescription; return }
        bottomPanel = .output; outputs[draft.id] = []; outputSize = 0; outputTruncated = false
        runningID = draft.id; error = nil
        runTask = Task { [weak self] in
            guard let self else { return }
            let start = Date()
            var baseline = draft.code
            defer {
                runningNotebookCell = nil; durations[draft.id] = Date().timeIntervalSince(start)
                if runningID == draft.id { runningID = nil }
                if advance, let cell { advanceNotebookCell(after: cell, draftID: draft.id) }
            }
            do {
                guard let version = connection?.pythonVersion else { throw LabError.message("Server Python version unavailable.") }
                for item in cells {
                    try Task.checkCancellation()
                    runningNotebookCell = item.index; notebookRecentCode[draft.id] = item.index
                    runStates[draft.id] = "本機執行中"
                    consume(.text("Cell \(item.index + 1) · Local Python \(version)\n", isError: false), id: draft.id)
                    let capture = NotebookRunOutput()
                    let localOK = try await localPython.runCell(code: item.code, name: draft.name + " · Cell \(item.index + 1)", version: version) { [weak self] value, isError in
                        await self?.consume(.text(value, isError: isError), id: draft.id)
                        await capture.append(.text(value, isError: isError))
                    }
                    var result = await capture.result()
                    if localOK {
                        runStates[draft.id] = "伺服器覆核中"
                        consume(.text("Local check passed → Server verification\n", isError: false), id: draft.id)
                        await capture.append(.clear)
                        try await service.execute(code: item.code) { [weak self] event in
                            await capture.append(event); await self?.consume(event, id: draft.id)
                        }
                        result = await capture.result()
                    } else { runStates[draft.id] = "本機錯誤 · 未送出" }
                    if let position = drafts.firstIndex(where: { $0.id == draft.id }), drafts[position].code == baseline {
                        var notebook = try NotebookDocument(baseline)
                        notebook.setOutputs(at: item.index, outputs: result.outputs, executionCount: result.count)
                        let json = try notebook.serialized(); drafts[position].code = json; baseline = json; persist()
                    }
                    if !localOK || !result.success { break }
                }
            } catch {
                if !Task.isCancelled && !closing { self.error = safeError(error); runStates[draft.id] = "執行失敗" }
            }
        }
    }
}
