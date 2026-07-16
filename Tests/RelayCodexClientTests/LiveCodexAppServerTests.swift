import Foundation
import Testing
@testable import RelayCodexClient

struct LiveCodexAppServerTests {
    @Test
    func listsThreadsFromTheInstalledCodexApp() async throws {
        guard ProcessInfo.processInfo.environment[
            "RELAY_RUN_LIVE_CODEX_TEST"
        ] == "1" else {
            return
        }

        let client = CodexAppServerClient()
        let threads = try await client.loadThreads(limit: 5)

        #expect(!threads.isEmpty)
        #expect(threads.allSatisfy { !$0.id.isEmpty })
    }
}
