import RelayCodexBridge
import Testing

struct RelaySpokenSummaryTests {
    @Test
    func shortPlainAnswerIsSpokenVerbatim() {
        #expect(
            RelaySpokenSummary.make(
                from: "Two worker tasks are active."
            ) == "Two worker tasks are active."
        )
    }

    @Test
    func leadsWithTheFirstSentencesAndDropsTheTail() {
        let answer = """
            The login task finished and tests pass. I merged it to main. \
            You can pull the branch whenever you like, and I can start the \
            next item, and there is plenty more detail after that which \
            should not be read aloud because it runs well past the spoken \
            summary limit for a single reply.
            """
        let spoken = RelaySpokenSummary.make(from: answer)

        #expect(spoken.hasPrefix("The login task finished and tests pass."))
        #expect(spoken.count <= RelaySpokenSummary.characterLimit)
        #expect(!spoken.contains("read aloud"))
    }

    @Test
    func stripsMarkdownBulletsHeadingsAndEmphasis() {
        let answer = """
            ## Status

            - **Login bug**: fixed
            - Docs: `updated`
            """
        let spoken = RelaySpokenSummary.make(from: answer)

        #expect(!spoken.contains("#"))
        #expect(!spoken.contains("*"))
        #expect(!spoken.contains("`"))
        #expect(!spoken.contains("-"))
        #expect(spoken.contains("Status"))
        #expect(spoken.contains("Login bug"))
    }

    @Test
    func stripsLinkSyntaxKeepingVisibleText() {
        let spoken = RelaySpokenSummary.make(
            from: "See [the PR](https://example.com/pr/1) for details."
        )

        #expect(!spoken.contains("http"))
        #expect(!spoken.contains("]("))
        #expect(spoken.contains("the PR"))
    }

    @Test
    func dropsFencedCodeBlocks() {
        let answer = """
            Here is the fix.

            ```swift
            let x = 1
            ```
            """
        let spoken = RelaySpokenSummary.make(from: answer)

        #expect(spoken.contains("Here is the fix."))
        #expect(!spoken.contains("let x"))
    }

    @Test
    func emptyAnswerProducesNothingToSpeak() {
        #expect(RelaySpokenSummary.make(from: "   \n  ").isEmpty)
    }

    @Test
    func caps_veryLongSingleSentenceAtAWordBoundary() {
        let answer = String(repeating: "word ", count: 200)
        let spoken = RelaySpokenSummary.make(from: answer)

        #expect(spoken.count <= RelaySpokenSummary.characterLimit)
        #expect(!spoken.hasSuffix(" "))
        #expect(!spoken.contains("wor\u{200B}")) // no mid-word cut marker
    }
}
