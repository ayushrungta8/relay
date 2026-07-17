import Foundation
import Testing
@testable import RelayApp

@MainActor
struct CodexDesktopFollowUpSenderTests {
    @Test
    func rejectsDeliveryWithoutAccessibilityPermission() async {
        let sender = CodexDesktopFollowUpSender(
            isAccessibilityTrusted: { false },
            openURL: { _ in true },
            frontmostBundleIdentifier: { "com.openai.codex" },
            typeAndSubmit: { _ in },
            sleep: { _ in }
        )

        await #expect(throws: CodexDesktopFollowUpError.accessibilityRequired) {
            try await sender.send(
                threadID: "worker",
                prompt: "Continue"
            )
        }
    }

    @Test
    func opensThreadThenTypesAndSubmitsPrompt() async throws {
        var openedURL: URL?
        var submittedPrompt: String?
        let sender = CodexDesktopFollowUpSender(
            isAccessibilityTrusted: { true },
            openURL: {
                openedURL = $0
                return true
            },
            frontmostBundleIdentifier: { "com.openai.codex" },
            typeAndSubmit: { submittedPrompt = $0 },
            sleep: { _ in }
        )

        try await sender.send(
            threadID: "worker-1",
            prompt: "Please continue"
        )

        #expect(openedURL?.absoluteString == "codex://threads/worker-1")
        #expect(submittedPrompt == "Please continue")
    }
}
