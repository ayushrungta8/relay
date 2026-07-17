import RelayCore

struct RelayPendingInteractionPresentation: Equatable {
    enum Action: Equatable {
        case answerQuestions
        case reviewApproval
        case resolving
        case openInCodex
    }

    let interaction: RelayPendingInteraction?
    let action: Action
    let explanation: String

    var isRelayOwned: Bool { interaction != nil }
    var allowsTaskManagement: Bool {
        interaction?.state == .pending
    }

    init(
        task: RelayTaskActivity,
        ownedInteraction: RelayPendingInteraction?
    ) {
        precondition(task.attentionState == .needsInput)
        if let ownedInteraction,
           ownedInteraction.threadID == task.id {
            interaction = ownedInteraction
            if ownedInteraction.state == .resolving {
                action = .resolving
                explanation = "Relay submitted your response and is waiting for Codex to continue."
                return
            }
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

    static func options(
        for question: RelayPendingQuestion
    ) -> [OptionEntry] {
        question.options.enumerated().map { index, option in
            OptionEntry(
                id: OptionID(questionID: question.id, index: index),
                option: option
            )
        }
    }

    static func isSelected(
        _ entry: OptionEntry,
        for question: RelayPendingQuestion,
        draft: RelayPendingAnswerDraft
    ) -> Bool {
        draft.answer(for: question.id) == entry.option.label
    }

    static func answerAccessibilityLabel(
        for question: RelayPendingQuestion
    ) -> String {
        "\(question.header), answer"
    }
}

extension RelayPendingInteractionPresentation {
    struct OptionID: Hashable {
        let questionID: String
        let index: Int
    }

    struct OptionEntry: Identifiable, Equatable {
        let id: OptionID
        let option: RelayPendingQuestionOption
    }
}
