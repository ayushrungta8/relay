import Testing
@testable import RelayApp

@MainActor
struct CommandComposerStateTests {
    @Test
    func draftNormalizesMutableTextForSubmission() {
        var draft = RelayCommandDraft(text: "  Open the project \n")

        #expect(draft.normalizedSubmission == "Open the project")

        draft.text = "\nRun the tests\t"

        #expect(draft.normalizedSubmission == "Run the tests")
    }

    @Test
    func draftRejectsWhitespaceOnlySubmission() {
        let draft = RelayCommandDraft(text: " \n\t ")

        #expect(draft.normalizedSubmission == nil)
    }

    @Test
    func submissionGateRejectsBlankAndBusyDrafts() {
        var gate = RelayCommandSubmissionGate()
        let blankDraft = RelayCommandDraft(text: " ")
        let commandDraft = RelayCommandDraft(text: "Open Calendar")

        let acceptedBlank = gate.beginSubmission(
            draft: blankDraft,
            phase: .idle
        )
        let acceptedWhileListening = gate.beginSubmission(
            draft: commandDraft,
            phase: .listening
        )
        let acceptedWhileSending = gate.beginSubmission(
            draft: commandDraft,
            phase: .sending
        )
        let acceptedWhileIdle = gate.beginSubmission(
            draft: commandDraft,
            phase: .idle
        )

        #expect(!acceptedBlank)
        #expect(!acceptedWhileListening)
        #expect(!acceptedWhileSending)
        #expect(acceptedWhileIdle)
    }

    @Test
    func submissionGateBlocksDuplicateUntilThePhaseCompletes() {
        var gate = RelayCommandSubmissionGate()
        let draft = RelayCommandDraft(text: "Open Calendar")

        let acceptedFirstSubmission = gate.beginSubmission(
            draft: draft,
            phase: .idle
        )
        let acceptedDuplicate = gate.beginSubmission(
            draft: draft,
            phase: .idle
        )

        gate.phaseDidChange(to: .sending)
        let acceptedWhileSending = gate.beginSubmission(
            draft: draft,
            phase: .sending
        )

        gate.phaseDidChange(to: .failed("Calendar was unavailable"))
        let acceptedRetry = gate.beginSubmission(
            draft: draft,
            phase: .failed("Calendar was unavailable")
        )

        #expect(acceptedFirstSubmission)
        #expect(!acceptedDuplicate)
        #expect(!acceptedWhileSending)
        #expect(acceptedRetry)
    }
}
