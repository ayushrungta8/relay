import Testing
@testable import RelayCore

struct CodexDeepLinkTests {
    @Test
    func buildsTheDesktopCodexThreadURL() {
        let url = CodexDeepLink.thread(
            id: "019f6759-d236-7962-9f6d-5f533fe1fc6e"
        )

        #expect(
            url?.absoluteString
                == "codex://threads/019f6759-d236-7962-9f6d-5f533fe1fc6e"
        )
        #expect(CodexDeepLink.thread(id: "") == nil)
    }
}
