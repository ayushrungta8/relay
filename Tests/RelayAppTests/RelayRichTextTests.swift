import Testing

@testable import RelayApp

@MainActor
struct RelayRichTextTests {
    @Test
    func stripsInternalDirectivesAndPreservesReadableStructure() {
        let source = """
            ## Completed

            - Fixed **focus** restoration
            - Updated `Sparkle`

            ::git-stage{cwd="/tmp/Relay"}
            """

        let rendered = String(RelayRichText.attributed(source).characters)

        #expect(rendered.contains("Completed"))
        #expect(rendered.contains("• Fixed focus restoration"))
        #expect(rendered.contains("• Updated Sparkle"))
        #expect(!rendered.contains("::git-stage"))
        #expect(rendered.contains("\n"))
    }

    @Test
    func plainSummaryCollapsesMarkdownAndWhitespace() {
        let source = "First **important** line\n\n- second item"

        #expect(
            RelayRichText.plain(source)
                == "First important line • second item"
        )
    }

    @Test
    func ordinaryDoubleColonTextIsNotRemoved() {
        let source = "Use the namespace std::filesystem."

        #expect(RelayRichText.sanitized(source) == source)
    }
}
