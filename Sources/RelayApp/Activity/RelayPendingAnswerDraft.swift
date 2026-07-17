import Foundation
import RelayCore

struct RelayPendingAnswerDraft: Equatable {
    private(set) var interactionID: String?
    private var answers: [String: String] = [:]

    init(interactionID: String?) {
        self.interactionID = interactionID
    }

    var isDirty: Bool {
        answers.values.contains {
            !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
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
