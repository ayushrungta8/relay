import Testing
@testable import RelayCore

struct RelayConversationalAttentionTests {
    @Test(arguments: [
        "Please review the plan and reply approved.",
        "Confirm before I continue.",
        "Tell me when the server is ready.",
    ])
    func explicitGatesNeedReply(_ text: String) {
        #expect(
            RelayConversationalAttentionRules.classify(text) == .needsReply
        )
    }

    @Test
    func plainCompletionDoesNotNeedReply() {
        #expect(
            RelayConversationalAttentionRules.classify(
                "Implemented the change. All tests pass."
            ) == .doesNotNeedReply
        )
    }

    @Test
    func genericQuestionIsAmbiguous() {
        #expect(
            RelayConversationalAttentionRules.classify(
                "Would you like me to add documentation?"
            ) == .ambiguous
        )
    }

    @Test(arguments: [
        "Please review the plan and reply approved.",
        "Respond with approved when you're ready.",
        "Say \"approved\" to continue.",
    ])
    func explicitApprovalRequestsSuggestOneClickApproval(_ text: String) {
        #expect(
            RelayConversationalAttentionRules.suggestedAction(for: text)
                == .approve
        )
    }

    @Test
    func generalReplyRequestDoesNotInventAnApprovalAction() {
        #expect(
            RelayConversationalAttentionRules.suggestedAction(
                for: "Please tell me which environment to use."
            ) == nil
        )
    }

    @Test
    func requestLanguageOutsideTheActionWindowUsesAI() {
        let text = "A quoted example says: please review. "
            + String(repeating: "Completed work. ", count: 200)

        #expect(
            RelayConversationalAttentionRules.classify(text) == .ambiguous
        )
    }

    @Test
    func inferredReplyOutranksUnreadCompletion() {
        let response = RelayTaskFinalResponse(
            turnID: "turn-1",
            text: "Should I continue?",
            fingerprint: "abc"
        )
        let activity = RelayTaskActivity(
            thread: CodexThread(
                id: "worker",
                preview: "Worker",
                cwd: "/tmp",
                updatedAt: 1,
                status: .idle
            ),
            hasUnreadCompletion: true,
            latestTurnStatus: .completed,
            latestFinalResponse: response,
            hasInferredReplyRequest: true
        )

        #expect(activity.attentionReason == .inferredReplyRequest)
        #expect(activity.attentionState == .needsInput)
    }

    @Test
    func structuredFlagOutranksInference() {
        let activity = RelayTaskActivity(
            thread: CodexThread(
                id: "worker",
                preview: "Worker",
                cwd: "/tmp",
                updatedAt: 1,
                status: .active,
                activeFlags: [.waitingOnUserInput]
            ),
            hasInferredReplyRequest: true
        )

        #expect(activity.attentionReason == .structuredInteraction)
    }
}
