import Foundation
import RelayCodexClient
import RelayCore
import Testing
@testable import RelayApp

struct RelayActivityStoreTests {
    @MainActor
    @Test
    func failedRefreshKeepsTheLastKnownSnapshotVisibleOffline() async {
        let monitoring = MonitoringStub(
            results: [
                .success(
                    RelayMonitoringSnapshot(
                        tasks: [
                            activity(
                                id: "worker",
                                updatedAt: 100,
                                status: .active
                            ),
                        ],
                        usage: nil
                    )
                ),
                .failure(StoreFixtureError.offline),
            ]
        )
        let store = RelayActivityStore(
            monitoring: monitoring,
            tasks: TaskOperationsStub(),
            connect: {}
        )

        await store.refresh()
        #expect(store.runningTasks.map(\.id) == ["worker"])
        #expect(store.connectionState.isConnected)

        await store.refresh()
        #expect(store.runningTasks.map(\.id) == ["worker"])
        #expect(store.connectionState.isOffline)
    }

    @Test
    func reconnectSchedulingUsesExponentialDelaysCappedAtThirtySeconds() {
        #expect(
            (0...7).map(RelayActivityStore.reconnectDelay(forAttempt:))
                == [
                    .seconds(1),
                    .seconds(2),
                    .seconds(4),
                    .seconds(8),
                    .seconds(16),
                    .seconds(30),
                    .seconds(30),
                    .seconds(30),
                ]
        )
    }

    @MainActor
    @Test
    func sendAndInterruptDelegateToTaskOperationsAndRefresh() async throws {
        let monitoring = MonitoringStub(
            results: [
                .success(.init(tasks: [], usage: nil)),
                .success(.init(tasks: [], usage: nil)),
            ]
        )
        let tasks = TaskOperationsStub()
        let store = RelayActivityStore(
            monitoring: monitoring,
            tasks: tasks,
            connect: {}
        )

        try await store.send(threadID: "worker", prompt: "  Continue  ")
        try await store.interrupt(threadID: "worker")

        #expect(
            await tasks.sentPrompts()
                == [SentPrompt(threadID: "worker", prompt: "Continue")]
        )
        #expect(await tasks.interruptedIDs() == ["worker"])
        #expect(await monitoring.snapshotCallCount() == 2)
        #expect(store.lastSelectedThreadID == "worker")
    }

    @MainActor
    @Test
    func transientSnapshotFailureSchedulesBoundedRecovery() async {
        let monitoring = MonitoringStub(
            results: [
                .success(.init(tasks: [], usage: nil)),
                .failure(StoreFixtureError.offline),
            ]
        )
        let sleeps = SleepRecorder()
        let store = RelayActivityStore(
            monitoring: monitoring,
            tasks: TaskOperationsStub(),
            connect: {},
            sleep: { duration in
                await sleeps.record(duration)
                throw CancellationError()
            }
        )

        await store.start()
        await store.refresh()
        for _ in 0..<100 {
            if await sleeps.durations().contains(.seconds(1)) {
                break
            }
            await Task.yield()
        }

        #expect(await sleeps.durations().contains(.seconds(1)))
    }

    private func activity(
        id: String,
        updatedAt: Int,
        status: CodexThreadStatus
    ) -> RelayTaskActivity {
        RelayTaskActivity(
            thread: CodexThread(
                id: id,
                preview: id,
                cwd: "/tmp",
                updatedAt: updatedAt,
                status: status
            )
        )
    }
}

private actor MonitoringStub: RelayActivityMonitoring {
    nonisolated let eventStream: AsyncStream<RelayMonitoringEvent>
    private var results: [Result<RelayMonitoringSnapshot, any Error>]
    private var snapshotCalls = 0

    init(results: [Result<RelayMonitoringSnapshot, any Error>]) {
        self.results = results
        eventStream = AsyncStream { _ in }
    }

    nonisolated func events() -> AsyncStream<RelayMonitoringEvent> {
        eventStream
    }

    func snapshot(limit: Int) async throws -> RelayMonitoringSnapshot {
        snapshotCalls += 1
        guard !results.isEmpty else {
            throw StoreFixtureError.missingResult
        }
        return try results.removeFirst().get()
    }

    func snapshotCallCount() -> Int {
        snapshotCalls
    }
}

private actor TaskOperationsStub: CodexTaskOperating {
    private var sent: [SentPrompt] = []
    private var interrupted: [String] = []

    func sendToTask(
        id: String,
        prompt: String
    ) async throws -> CodexTaskLaunch {
        sent.append(SentPrompt(threadID: id, prompt: prompt))
        return CodexTaskLaunch(
            thread: CodexThread(
                id: id,
                preview: prompt,
                cwd: "/tmp",
                updatedAt: 1,
                status: .active
            ),
            turnID: "turn"
        )
    }

    func interruptTask(id: String) async throws {
        interrupted.append(id)
    }

    func sentPrompts() -> [SentPrompt] {
        sent
    }

    func interruptedIDs() -> [String] {
        interrupted
    }
}

private struct SentPrompt: Sendable, Equatable {
    let threadID: String
    let prompt: String
}

private actor SleepRecorder {
    private var recorded: [Duration] = []

    func record(_ duration: Duration) {
        recorded.append(duration)
    }

    func durations() -> [Duration] {
        recorded
    }
}

private enum StoreFixtureError: Error {
    case offline
    case missingResult
}
