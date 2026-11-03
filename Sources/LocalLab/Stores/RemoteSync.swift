import Foundation
import AppKit

extension WorkspaceStore {
    var browsingRemote: Bool { selection == Self.remoteBrowserID }
    func remoteSelectionID(_ entry: RemoteEntry) -> UUID {
        drafts.first(where: { $0.remotePath == entry.path })?.id ?? entry.selectionID
    }
    var remoteTreeRoots: [RemoteEntry] { directoryCache[""] ?? [] }
    var uncataloguedRemoteDrafts: [ScriptDraft] {
        let paths = Set(directoryCache.values.flatMap { $0.map(\.path) })
        return drafts.filter { $0.remotePath != nil && !paths.contains($0.remotePath!) }
    }
    func handleSelection() async {
        if let selectedID = selection, selected == nil, !browsingRemote,
           let entry = directoryCache.values.flatMap({ $0 }).first(where: { remoteSelectionID($0) == selectedID }) {
            if !isReady { error = "請先連線，再開啟此遠端檔案。"; return }
            await openRemote(entry)
        } else { await refreshRemote() }
    }
    func setDirectoryCache(_ path: String, entries: [RemoteEntry]) {
        let fresh = Set(entries.map(\.path))
        let removed = (directoryCache[path] ?? []).filter { !fresh.contains($0.path) }
        for entry in removed where entry.type == "directory" {
            for key in Array(directoryCache.keys) where key == entry.path || key.hasPrefix(entry.path + "/") {
                directoryCache[key] = nil; expandedRemoteFolders.remove(key)
            }
        }
        directoryCache[path] = entries
    }
    func expandFolder(_ path: String, expanded: Bool) {
        if !expanded { expandedRemoteFolders.remove(path); return }
        expandedRemoteFolders.insert(path)
        guard isReady, !loadingRemoteFolders.contains(path), let remoteFiles else { return }
        loadingRemoteFolders.insert(path)
        Task {
            defer { loadingRemoteFolders.remove(path) }
            do { setDirectoryCache(path, entries: try await remoteFiles.remoteDirectory(path)) }
            catch { self.error = safeError(error) }
        }
    }
    func startSyncing() {
        syncTask?.cancel()
        syncTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 15_000_000_000)
                guard !Task.isCancelled, let self, isReady else { return }
                await refreshRemote()
            }
        }
    }
    func refreshRemote() async {
        guard isReady, !fileBusy, let remoteFiles else { return }
        fileBusy = true; defer { fileBusy = false }
        let path = remoteDirectoryPath
        do {
            let entries = try await remoteFiles.remoteDirectory(path)
            if remoteDirectoryPath == path { remoteEntries = entries; lastSynced = Date() }
            setDirectoryCache(path, entries: entries)
            if !path.isEmpty { setDirectoryCache("", entries: try await remoteFiles.remoteDirectory("")) }
            for folder in expandedRemoteFolders.sorted() where folder != path && !folder.isEmpty {
                do { setDirectoryCache(folder, entries: try await remoteFiles.remoteDirectory(folder)) }
                catch { loadingRemoteFolders.remove(folder) }
            }
            await refreshSelectedFile(using: remoteFiles)
        } catch { self.error = safeError(error) }
    }
    private func refreshSelectedFile(using files: RemoteFileService) async {
        guard let draft = selected, let path = draft.remotePath else { return }
        do {
            let remote = try await files.remoteFile(path)
            guard let index = drafts.firstIndex(where: { $0.id == draft.id }) else { return }
            if drafts[index].code == remote.content {
                drafts[index].remoteBaseContent = remote.content; drafts[index].remoteModified = remote.entry.lastModified
                conflicts[draft.id] = nil
            } else if drafts[index].isRemoteDirty {
                if remote.content != drafts[index].remoteBaseContent { conflicts[draft.id] = remote } else { conflicts[draft.id] = nil }
            } else {
                drafts[index].code = remote.content; drafts[index].remoteBaseContent = remote.content
                drafts[index].remoteModified = remote.entry.lastModified
                conflicts[draft.id] = nil; syncNotice = "已更新遠端檔案：\(draft.name)"
            }
            persist()
        } catch is RemoteFileMissing {
            // A confirmed missing file must disappear even if a folder refresh failed.
            for directory in Array(directoryCache.keys) {
                directoryCache[directory]?.removeAll { $0.path == path }
            }
            remoteEntries.removeAll { $0.path == path }
            guard let index = drafts.firstIndex(where: { $0.id == draft.id && $0.remotePath == path }) else { return }
            let fileURL = URL(fileURLWithPath: draft.name)
            let stem = fileURL.deletingPathExtension().lastPathComponent + ".deleted-copy"
            let suffix = fileURL.pathExtension.isEmpty ? "" : "." + fileURL.pathExtension
            var name = stem + suffix
            var counter = 2
            while drafts.contains(where: { $0.name == name }) { name = stem + "-\(counter)" + suffix; counter += 1 }
            drafts[index].id = UUID(); drafts[index].name = name
            drafts[index].remotePath = nil; drafts[index].remoteBaseContent = nil; drafts[index].remoteModified = nil
            conflicts[draft.id] = nil
            if selection == draft.id { selection = drafts[index].id }
            syncNotice = "遠端檔案已移除，已保留本機副本：\(name)"; persist()
        } catch {
            // Preserve cached contents on transient network or permission failures.
            self.error = "遠端檔案無法同步；本機內容已保留。\n" + safeError(error)
        }
    }
    func showRemoteDirectory(_ path: String) async {
        guard !fileBusy else { return }
        remoteDirectoryPath = path; selection = Self.remoteBrowserID
        await refreshRemote()
    }
    func openRemote(_ entry: RemoteEntry) async {
        if entry.type == "directory" { await showRemoteDirectory(entry.path); return }
        guard isReady, !fileBusy, let remoteFiles else { return }
        if let draft = drafts.first(where: { $0.remotePath == entry.path }) {
            selection = draft.id; await refreshRemote(); return
        }
        fileBusy = true; defer { fileBusy = false }
        do {
            let remote = try await remoteFiles.remoteFile(entry.path)
            let draft = ScriptDraft(id: remote.entry.selectionID, name: remote.entry.name, code: remote.content, remotePath: remote.entry.path, remoteModified: remote.entry.lastModified, remoteBaseContent: remote.content)
            drafts.append(draft); selection = draft.id; persist()
        } catch { self.error = safeError(error) }
    }
    func saveSelectedRemote() async {
        guard isReady, !fileBusy, let draft = selected, let path = draft.remotePath, let baseline = draft.remoteBaseContent, let remoteFiles else { return }
        fileBusy = true; defer { fileBusy = false }
        do {
            let remote = try await remoteFiles.saveRemoteFile(path: path, content: draft.code, expectedContent: baseline)
            guard let index = drafts.firstIndex(where: { $0.id == draft.id }) else { return }
            // Edits made during the request remain dirty against the newly committed baseline.
            if drafts[index].code == draft.code { drafts[index].code = remote.content }
            drafts[index].remoteBaseContent = remote.content; drafts[index].remoteModified = remote.entry.lastModified
            conflicts[draft.id] = nil; syncNotice = "已儲存至遠端：\(draft.name)"; lastSynced = Date(); persist()
            remoteEntries = try await remoteFiles.remoteDirectory(remoteDirectoryPath); setDirectoryCache(remoteDirectoryPath, entries: remoteEntries)
        } catch let conflict as RemoteConflict { conflicts[draft.id] = conflict.file }
        catch { self.error = safeError(error) }
    }
    func saveAsRemote(name: String) async -> Bool {
        guard isReady, !fileBusy, let draft = selected, let remoteFiles else { return false }
        fileBusy = true; defer { fileBusy = false }
        do {
            let path = try RemotePath.joined(remoteDirectoryPath, name: name)
            let remote = try await remoteFiles.createRemoteFile(path: path, content: draft.code)
            guard let index = drafts.firstIndex(where: { $0.id == draft.id }) else { return false }
            drafts[index].name = remote.entry.name; drafts[index].remotePath = remote.entry.path
            drafts[index].remoteBaseContent = remote.content; drafts[index].remoteModified = remote.entry.lastModified
            conflicts[draft.id] = nil; syncNotice = "已建立遠端檔案：\(remote.entry.name)"; persist()
            remoteEntries = try await remoteFiles.remoteDirectory(remoteDirectoryPath); setDirectoryCache(remoteDirectoryPath, entries: remoteEntries); lastSynced = Date()
            return true
        } catch { self.error = safeError(error); return false }
    }
    func createRemoteDocument(name: String) async -> Bool {
        guard isReady, !fileBusy, let remoteFiles else { return false }
        let directory = remoteDirectoryPath
        fileBusy = true; defer { fileBusy = false }
        do {
            let path = try RemotePath.joined(directory, name: name)
            let remote = try await remoteFiles.createRemoteFile(path: path, content: "")
            let draft = ScriptDraft(id: remote.entry.selectionID, name: remote.entry.name, code: remote.content,
                                    remotePath: path, remoteModified: remote.entry.lastModified, remoteBaseContent: remote.content)
            // Preserve any cached local edits even if a previously deleted path is reused.
            if let index = drafts.firstIndex(where: { $0.remotePath == path }) {
                drafts[index].id = UUID(); drafts[index].remotePath = nil
                drafts[index].remoteBaseContent = nil; drafts[index].remoteModified = nil
            }
            drafts.append(draft)
            var entries = directoryCache[directory] ?? remoteEntries
            entries.removeAll { $0.path == path }; entries.append(remote.entry)
            entries.sort { $0.type == "directory" && $1.type != "directory" || ($0.type == "directory") == ($1.type == "directory") && $0.name.localizedStandardCompare($1.name) == .orderedAscending }
            setDirectoryCache(directory, entries: entries)
            if remoteDirectoryPath == directory { remoteEntries = entries }
            selection = draft.id; lastSynced = Date(); error = nil
            syncNotice = "已建立遠端檔案：\(draft.name)"; persist()
            return true
        } catch { self.error = safeError(error); return false }
    }
    func createFolder(name: String) async -> Bool {
        guard isReady, !fileBusy, let remoteFiles else { return false }
        fileBusy = true; defer { fileBusy = false }
        do {
            try await remoteFiles.createRemoteDirectory(path: RemotePath.joined(remoteDirectoryPath, name: name))
            remoteEntries = try await remoteFiles.remoteDirectory(remoteDirectoryPath); setDirectoryCache(remoteDirectoryPath, entries: remoteEntries); lastSynced = Date()
            return true
        } catch { self.error = safeError(error); return false }
    }
    func resolveConflictKeepingCopy() {
        guard let draft = selected, let remote = conflicts[draft.id], let index = drafts.firstIndex(where: { $0.id == draft.id }) else { return }
        let fileURL = URL(fileURLWithPath: draft.name)
        let copyName = fileURL.deletingPathExtension().lastPathComponent + ".local-copy" + (fileURL.pathExtension.isEmpty ? "" : "." + fileURL.pathExtension)
        let copy = ScriptDraft(name: copyName, code: draft.code)
        drafts.append(copy)
        drafts[index].code = remote.content; drafts[index].remoteBaseContent = remote.content
        drafts[index].remoteModified = remote.entry.lastModified; conflicts[draft.id] = nil
        syncNotice = "本機修改已保留為草稿副本；已載入遠端版本。"; persist()
    }
}
