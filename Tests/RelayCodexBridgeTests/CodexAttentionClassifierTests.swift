import Testing
@testable import RelayCodexBridge

struct CodexAttentionClassifierTests {
    @Test
    func decodesHighConfidencePositive() throws {
        let result = try CodexAttentionClassifier.decode(
            #"{"needs_reply":true,"confidence":"high","reason":"approval gate"}"#
        )

        #expect(result.needsReply)
        #expect(result.reason == "approval gate")
    }

    @Test
    func lowConfidenceCannotPromoteAttention() throws {
        let result = try CodexAttentionClassifier.decode(
            """
            ```json
            {"needs_reply":true,"confidence":"low","reason":"unclear"}
            ```
            """
        )

        #expect(!result.needsReply)
    }

    @Test
    func rejectsNonJSONOutput() {
        #expect(throws: CodexAttentionClassifierError.malformedResponse) {
            try CodexAttentionClassifier.decode("probably")
        }
    }
}
