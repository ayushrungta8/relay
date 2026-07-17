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

    @Test
    func enrichesRunningDesktopThreadsFromSharedRollouts() async throws {
        guard ProcessInfo.processInfo.environment[
            "RELAY_RUN_LIVE_CODEX_TEST"
        ] == "1" else {
            return
        }

        let client = PersistentCodexAppServerClient()
        try await client.start()
        let monitoring = CodexMonitoringClient(client: client)
        let snapshot = try await monitoring.snapshot(limit: 10)
        await client.stop()

        #expect(snapshot.tasks.contains { $0.attentionState == .running })
        #expect(snapshot.tokenUsageByThreadID.values.contains {
            $0.contextPercentage != nil
        })
        #expect(snapshot.usage?.primary != nil)
    }
}
