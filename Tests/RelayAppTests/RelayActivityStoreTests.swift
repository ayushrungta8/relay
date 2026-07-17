import Foundation
import RelayBrain
import RelayCodexClient
import RelayCore
import Testing
@testable import RelayApp

struct RelayActivityStoreTests {
    @MainActor
    @Test
    func exposesCurrentAttentionUsageAndTaskReferenceContext() async {
        let usage = RelayUsageSnapshot(
            limitID: "codex",
            limitName: "Codex",
            primary: RelayRateLimitWindow(
                usedPercent: 71,
                windowDurationMins: 300,
                resetsAt: 1_784_220_000
            ),
            secondary: nil,
            resetCreditsAvailableCount: 1
        )
        let monitoring = MonitoringStub(
            results: [
                .success(
                    .init(
                        tasks: [
                            RelayTaskActivity(
                                thread: CodexThread(
                                    id: "waiting",
                                    name: "Waiting task",
                                    preview: "Waiting task",
                                    cwd: "/Projects/Relay",
                                    updatedAt: 100,
                                    status: .active,
                                    activeFlags: [.waitingOnUserInput]
                                )
                            ),
                        ],
                        usage: usage
                    )
                ),
            ]
        )
        let store = RelayActivityStore(
            monitoring: monitoring,
            tasks: TaskOperationsStub(),
            connect: {}
        )

        await store.refresh()
        await store.select(threadID: "waiting")

        let reader: any RelaySupervisionStateReading = store
        #expect(await reader.attentionInbox().map(\.id) == ["waiting"])
        #expect(await reader.currentUsage()?.primary?.usedPercent == 71)
        #expect(
            await reader.taskReferenceContext()
                == RelayTaskReferenceContext(
                    selectedTaskID: "waiting",
                    lastInteractedTaskID: "waiting"
                )
        )
    }

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

    @MainActor
    @Test
    func successfulRefreshCancelsScheduledReconnect() async {
        let monitoring = MonitoringStub(
            results: [
                .failure(StoreFixtureError.offline),
                .success(.init(tasks: [], usage: nil)),
            ]
        )
        let sleepProbe = ReconnectSleepProbe()
        let store = RelayActivityStore(
            monitoring: monitoring,
            tasks: TaskOperationsStub(),
            connect: {},
            sleep: { duration in
                try await sleepProbe.sleep(for: duration)
            }
        )

        await store.start()
        for _ in 0..<100 {
            if await sleepProbe.hasStartedReconnect() {
                break
            }
            await Task.yield()
        }

        await store.refresh()
        for _ in 0..<100 {
            if await sleepProbe.wasReconnectCancelled() {
                break
            }
            await Task.yield()
        }

        #expect(store.connectionState.isConnected)
        #expect(await sleepProbe.wasReconnectCancelled())
    }

    @MainActor
    @Test
    func retryConnectionBypassesDelayedReconnectAndRecoversTransport() async {
        let monitoring = MonitoringStub(
            results: [.success(.init(tasks: [], usage: nil))]
        )
        let connector = FailingThenSuccessfulConnector()
        let sleepProbe = ReconnectSleepProbe()
        let store = RelayActivityStore(
            monitoring: monitoring,
            tasks: TaskOperationsStub(),
            connect: { try await connector.connect() },
            sleep: { duration in
                try await sleepProbe.sleep(for: duration)
            }
        )

        await store.start()
        for _ in 0..<100 where !(await sleepProbe.hasStartedReconnect()) {
            await Task.yield()
        }

        await store.retryConnection()

        #expect(await connector.attemptCount() == 2)
        #expect(await sleepProbe.wasReconnectCancelled())
        #expect(await monitoring.snapshotCallCount() == 1)
        #expect(store.connectionState.isConnected)
    }

    @MainActor
    @Test
    func coalescesOverlappingRefreshAndImmediatelyReruns() async {
        let monitoring = SuspendedMonitoringStub()
        let store = RelayActivityStore(
            monitoring: monitoring,
            tasks: TaskOperationsStub(),
            connect: {}
        )

        let first = Task { await store.refresh() }
        await monitoring.waitForCall(1)
        await store.refresh()
        await monitoring.resumeCall(1, snapshot: .init(tasks: [], usage: nil))
        await monitoring.waitForCall(2)
        await monitoring.resumeCall(2, snapshot: .init(tasks: [], usage: nil))
        await first.value

        #expect(await monitoring.callCount() == 2)
    }

    @MainActor
    @Test
    func replaysStatusEventReceivedDuringSuspendedSnapshot() async {
        let initial = activity(id: "worker", updatedAt: 1, status: .active)
        let monitoring = SuspendedMonitoringStub()
        let store = RelayActivityStore(
            monitoring: monitoring,
            tasks: TaskOperationsStub(),
            connect: {}
        )
        let seed = Task { await store.start() }
        await monitoring.waitForCall(1)
        await monitoring.resumeCall(1, snapshot: .init(tasks: [initial], usage: nil))
        await seed.value

        let refresh = Task { await store.refresh() }
        await monitoring.waitForCall(2)
        await monitoring.emit(.threadStatusChanged(
            threadID: "worker",
            status: .active,
            activeFlags: [.waitingOnUserInput]
        ))
        await Task.yield()
        await monitoring.resumeCall(2, snapshot: .init(tasks: [initial], usage: nil))
        await refresh.value

        #expect(store.attentionTasks.first?.attentionState == .needsInput)
    }

    @MainActor
    @Test
    func unknownThreadStatusSchedulesCoalescedRead() async {
        let monitoring = SuspendedMonitoringStub()
        let store = RelayActivityStore(
            monitoring: monitoring,
            tasks: TaskOperationsStub(),
            connect: {}
        )
        let start = Task { await store.start() }
        await monitoring.waitForCall(1)
        await monitoring.emit(.threadStatusChanged(
            threadID: "new-worker",
            status: .active,
            activeFlags: []
        ))
        await monitoring.resumeCall(1, snapshot: .init(tasks: [], usage: nil))
        await monitoring.waitForCall(2)
        await monitoring.resumeCall(2, snapshot: .init(tasks: [], usage: nil))
        await start.value

        #expect(await monitoring.callCount() == 2)
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

private actor SuspendedMonitoringStub: RelayActivityMonitoring {
    nonisolated let eventStream: AsyncStream<RelayMonitoringEvent>
    private let eventContinuation: AsyncStream<RelayMonitoringEvent>.Continuation
    private var calls = 0
    private var continuations: [Int: CheckedContinuation<RelayMonitoringSnapshot, Never>] = [:]

    init() {
        let pair = AsyncStream<RelayMonitoringEvent>.makeStream()
        eventStream = pair.stream
        eventContinuation = pair.continuation
    }

    nonisolated func events() -> AsyncStream<RelayMonitoringEvent> { eventStream }

    func snapshot(limit: Int) async -> RelayMonitoringSnapshot {
        calls += 1
        let call = calls
        return await withCheckedContinuation { continuations[call] = $0 }
    }

    func waitForCall(_ expected: Int) async {
        while calls < expected { await Task.yield() }
    }

    func resumeCall(_ call: Int, snapshot: RelayMonitoringSnapshot) {
        continuations.removeValue(forKey: call)?.resume(returning: snapshot)
    }

    func emit(_ event: RelayMonitoringEvent) { eventContinuation.yield(event) }
    func callCount() -> Int { calls }
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

private actor ReconnectSleepProbe {
    private var reconnectStarted = false
    private var reconnectCancelled = false
    private var reconnectContinuation:
        CheckedContinuation<Void, any Error>?

    func sleep(for duration: Duration) async throws {
        if duration == .seconds(30) {
            throw CancellationError()
        }
        reconnectStarted = true
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                reconnectContinuation = continuation
            }
        } onCancel: {
            Task {
                await self.cancelReconnect()
            }
        }
    }

    func hasStartedReconnect() -> Bool {
        reconnectStarted
    }

    func wasReconnectCancelled() -> Bool {
        reconnectCancelled
    }

    private func cancelReconnect() {
        reconnectCancelled = true
        reconnectContinuation?.resume(throwing: CancellationError())
        reconnectContinuation = nil
    }
}

private actor FailingThenSuccessfulConnector {
    private var attempts = 0

    func connect() throws {
        attempts += 1
        if attempts == 1 {
            throw StoreFixtureError.offline
        }
    }

    func attemptCount() -> Int { attempts }
}

private enum StoreFixtureError: Error {
    case offline
    case missingResult
}
