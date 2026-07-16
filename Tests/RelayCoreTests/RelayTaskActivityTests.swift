import Foundation
import Testing
@testable import RelayCore

struct RelayTaskActivityTests {
    @Test
    func decodesActiveFlagsAndPrioritizesWaitingTasks() throws {
        let thread = try JSONDecoder().decode(
            CodexThread.self,
            from: Data(
                """
                {
                  "id": "worker-1",
                  "name": "Review monitoring",
                  "preview": "Review monitoring",
                  "cwd": "/Users/ayushrungta/Work/Relay",
                  "updatedAt": 1784210400,
                  "status": {
                    "type": "active",
                    "activeFlags": [
                      "waitingOnApproval",
                      "waitingOnUserInput"
                    ]
                  }
                }
                """.utf8
            )
        )

        let activity = RelayTaskActivity(
            thread: thread,
            latestUpdate: "Waiting for a decision.",
            hasUnreadCompletion: true
        )

        #expect(
            thread.activeFlags
                == [.waitingOnApproval, .waitingOnUserInput]
        )
        #expect(activity.attentionState == .needsInput)
        #expect(
            RelayTaskAttentionState.needsInput.priority
                > RelayTaskAttentionState.failed.priority
        )
        #expect(
            RelayTaskAttentionState.failed.priority
                > RelayTaskAttentionState.ready.priority
        )
        #expect(
            RelayTaskAttentionState.ready.priority
                > RelayTaskAttentionState.running.priority
        )
        #expect(
            RelayTaskAttentionState.running.priority
                > RelayTaskAttentionState.idle.priority
        )
    }

    @Test
    func derivesFailedReadyRunningAndIdleStates() {
        #expect(activity(status: .systemError).attentionState == .failed)
        #expect(
            activity(status: .idle, unread: true).attentionState == .ready
        )
        #expect(activity(status: .active).attentionState == .running)
        #expect(activity(status: .notLoaded).attentionState == .idle)
    }

    @Test
    func computesContextPercentageFromLastTurnOnlyWhenWindowIsNonzero() {
        let total = RelayTokenUsageBreakdown(
            inputTokens: 80_000,
            cachedInputTokens: 20_000,
            outputTokens: 10_000,
            reasoningOutputTokens: 5_000,
            totalTokens: 95_000
        )
        let last = RelayTokenUsageBreakdown(
            inputTokens: 30_000,
            cachedInputTokens: 5_000,
            outputTokens: 5_000,
            reasoningOutputTokens: 2_000,
            totalTokens: 35_000
        )

        let usage = RelayThreadTokenUsage(
            total: total,
            last: last,
            modelContextWindow: 200_000
        )
        let unavailable = RelayThreadTokenUsage(
            total: total,
            last: last,
            modelContextWindow: 0
        )

        #expect(usage.contextPercentage == 17.5)
        #expect(unavailable.contextPercentage == nil)
    }

    private func activity(
        status: CodexThreadStatus,
        unread: Bool = false
    ) -> RelayTaskActivity {
        RelayTaskActivity(
            thread: CodexThread(
                id: "worker-\(status.rawValue)",
                preview: "Fixture",
                cwd: "/tmp",
                updatedAt: 1,
                status: status
            ),
            hasUnreadCompletion: unread
        )
    }
}
