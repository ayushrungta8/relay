import RelayCore

struct RelayPendingInteractionPresentation: Equatable {
    enum Action: Equatable {
        case answerQuestions
        case reviewApproval
        case openInCodex
    }

    let interaction: RelayPendingInteraction?
    let action: Action
    let explanation: String

    var isRelayOwned: Bool { interaction != nil }

    init(
        task: RelayTaskActivity,
        ownedInteraction: RelayPendingInteraction?
    ) {
        precondition(task.attentionState == .needsInput)
        if let ownedInteraction,
           ownedInteraction.threadID == task.id {
            interaction = ownedInteraction
            switch ownedInteraction.kind {
            case .questions:
                action = .answerQuestions
                explanation = "Answer in Relay to continue this task."
            case .approval:
                action = .reviewApproval
                explanation = "Review this request in Relay to continue."
            }
        } else {
            interaction = nil
            action = .openInCodex
            explanation = "This request belongs to another Codex client. Open the task in Codex to respond."
        }
    }
}
