import Observation

@MainActor
@Observable
final class RelayPanelDraftStore {
    private var pendingDrafts: [String: RelayPendingAnswerDraft] = [:]
    private var followUpDrafts: [String: RelayTaskCardFollowUpState] = [:]
    private(set) var orphanedDrafts: [RelayOrphanedDraft] = []

    var hasDirtyDraft: Bool {
        pendingDrafts.values.contains(where: \.isDirty)
            || followUpDrafts.values.contains(where: \.isDirty)
    }

    var canDismiss: Bool { !hasDirtyDraft }

    func pendingDraft(interactionID: String) -> RelayPendingAnswerDraft {
        pendingDrafts[interactionID]
            ?? RelayPendingAnswerDraft(interactionID: interactionID)
    }

    func setPendingAnswer(
        _ answer: String,
        questionID: String,
        interactionID: String
    ) {
        var draft = pendingDraft(interactionID: interactionID)
        draft.setAnswer(answer, for: questionID)
        pendingDrafts[interactionID] = draft
    }

    func discardPendingAnswers(interactionID: String) {
        pendingDrafts.removeValue(forKey: interactionID)
        orphanedDrafts.removeAll {
            $0.kind == .pendingAnswer && $0.ownerID == interactionID
        }
    }

    func followUp(threadID: String) -> RelayTaskCardFollowUpState {
        followUpDrafts[threadID] ?? RelayTaskCardFollowUpState()
    }

    func beginFollowUp(
        threadID: String,
        allowsTaskManagement: Bool = true
    ) {
        var state = followUp(threadID: threadID)
        state.beginFollowUp(allowsTaskManagement: allowsTaskManagement)
        followUpDrafts[threadID] = state
    }

    func setFollowUp(_ value: String, threadID: String) {
        var state = followUp(threadID: threadID)
        state.draft = value
        followUpDrafts[threadID] = state
    }

    func synchronizeFollowUp(
        threadID: String,
        allowsTaskManagement: Bool
    ) {
        var state = followUp(threadID: threadID)
        state.synchronize(allowsTaskManagement: allowsTaskManagement)
        followUpDrafts[threadID] = state
    }

    func discardFollowUp(threadID: String) {
        followUpDrafts.removeValue(forKey: threadID)
        orphanedDrafts.removeAll {
            $0.kind == .followUp && $0.ownerID == threadID
        }
    }

    func reconcile(
        liveThreadIDs: Set<String>,
        liveInteractionIDs: Set<String>
    ) {
        pendingDrafts = pendingDrafts.filter { interactionID, draft in
            liveInteractionIDs.contains(interactionID) || draft.isDirty
        }
        followUpDrafts = followUpDrafts.filter { threadID, draft in
            liveThreadIDs.contains(threadID) || draft.isDirty
        }

        let pending: [RelayOrphanedDraft] = pendingDrafts.compactMap {
            interactionID, draft in
            guard draft.isDirty,
                  !liveInteractionIDs.contains(interactionID) else {
                return nil
            }
            return RelayOrphanedDraft(
                kind: .pendingAnswer,
                ownerID: interactionID
            )
        }
        let followUps: [RelayOrphanedDraft] = followUpDrafts.compactMap {
            threadID, draft in
            guard draft.isDirty, !liveThreadIDs.contains(threadID) else {
                return nil
            }
            return RelayOrphanedDraft(
                kind: .followUp,
                ownerID: threadID
            )
        }
        orphanedDrafts = (pending + followUps).sorted { $0.id < $1.id }
    }

    func discard(_ orphan: RelayOrphanedDraft) {
        switch orphan.kind {
        case .pendingAnswer:
            discardPendingAnswers(interactionID: orphan.ownerID)
        case .followUp:
            discardFollowUp(threadID: orphan.ownerID)
        }
    }
}
