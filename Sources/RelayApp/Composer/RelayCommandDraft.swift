import Foundation

struct RelayCommandDraft {
    var text: String

    var normalizedSubmission: String? {
        let submission = text.trimmingCharacters(
            in: .whitespacesAndNewlines
        )
        return submission.isEmpty ? nil : submission
    }
}
