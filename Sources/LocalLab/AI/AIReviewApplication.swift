import Foundation

@MainActor
extension WorkspaceStore {
    func applyAIProposal(_ result: AIReviewResult) throws {
        guard result.request.mode == .edit else { throw AIReviewError.reviewOnly }
        guard result.hasChanges, let code = result.proposedCode else { throw AIReviewError.noChanges }
        guard runningID == nil, !fileBusy else { throw AIReviewError.documentBusy }
        guard selection == result.request.snapshot.draftID, result.request.snapshot.matches(selected) else { throw AIReviewError.documentChanged }
        updateCode(code)
        // Remote base content is deliberately preserved: ⌘S retains the existing conflict checks.
        persist()
    }
    func undoAIProposal(_ result: AIReviewResult) throws {
        guard result.request.mode == .edit, let applied = result.proposedCode else { throw AIReviewError.reviewOnly }
        guard runningID == nil, !fileBusy else { throw AIReviewError.documentBusy }
        guard let current = selected, selection == result.request.snapshot.draftID,
              current.name == result.request.snapshot.filename, current.remotePath == result.request.snapshot.remotePath,
              current.code == applied else { throw AIReviewError.documentChanged }
        updateCode(result.request.snapshot.code); persist()
    }
}
