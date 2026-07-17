import Observation

@MainActor
@Observable
final class RelayPanelDraftStore {
    private var pendingDrafts: [String: RelayPendingAnswerDraft] = [:]
    private var followUpDrafts: [String: RelayTaskCardFollowUpState] = [:]

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
    }
}
