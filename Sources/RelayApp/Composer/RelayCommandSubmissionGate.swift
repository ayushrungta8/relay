struct RelayCommandSubmissionGate {
    private var mostRecentSubmission: String?

    func canBeginSubmission(
        draft: RelayCommandDraft,
        phase: RelayComposerPhase
    ) -> Bool {
        guard phaseAllowsSubmission(phase) else {
            return false
        }
        guard let submission = draft.normalizedSubmission else {
            return false
        }
        return submission != mostRecentSubmission
    }

    mutating func beginSubmission(
        draft: RelayCommandDraft,
        phase: RelayComposerPhase
    ) -> Bool {
        guard canBeginSubmission(draft: draft, phase: phase) else {
            return false
        }

        mostRecentSubmission = draft.normalizedSubmission
        return true
    }

    mutating func phaseDidChange(to phase: RelayComposerPhase) {
        switch phase {
        case .idle, .failed:
            mostRecentSubmission = nil
        case .listening, .sending:
            break
        }
    }

    private func phaseAllowsSubmission(
        _ phase: RelayComposerPhase
    ) -> Bool {
        switch phase {
        case .idle, .failed:
            true
        case .listening, .sending:
            false
        }
    }
}
