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
    var allowsTaskManagement: Bool { isRelayOwned }

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

struct RelayPendingAnswerDraft: Equatable {
    private(set) var interactionID: String?
    private var answers: [String: String] = [:]

    init(interactionID: String?) {
        self.interactionID = interactionID
    }

    mutating func synchronize(interactionID: String?) {
        guard self.interactionID != interactionID else { return }
        clear()
        self.interactionID = interactionID
    }

    mutating func clear() {
        answers.removeAll(keepingCapacity: false)
    }

    mutating func setAnswer(_ answer: String, for questionID: String) {
        answers[questionID] = answer
    }

    func answer(for questionID: String) -> String {
        answers[questionID] ?? ""
    }

    func canSubmit(questions: [RelayPendingQuestion]) -> Bool {
        questions.allSatisfy { question in
            !answer(for: question.id)
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .isEmpty
        }
    }

    func payload(
        questions: [RelayPendingQuestion]
    ) -> [String: [String]] {
        Dictionary(
            uniqueKeysWithValues: questions.map {
                ($0.id, [answer(for: $0.id)])
            }
        )
    }
}
