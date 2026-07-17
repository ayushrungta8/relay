import Foundation
import RelayCodexClient
import RelayCodexBridge
import RelayCore
import Testing
@testable import RelayApp

struct RelayAppModelTests {
    @MainActor
    @Test
    func refreshPublishesTheLatestCodexThreads() async {
        let provider = StubThreadProvider(
            threads: [
                CodexThread.fixture(
                    id: "thread-1",
                    preview: "Build Relay"
                ),
            ]
        )
        let model = RelayAppModel(providerFactory: { provider })

        await model.refresh()

        #expect(model.state == .loaded)
        #expect(model.threads.map(\.id) == ["thread-1"])
    }

    @MainActor
    @Test
    func refreshPlacesActiveTasksBeforeNewerIdleTasks() async {
        let provider = StubThreadProvider(
            threads: [
                CodexThread.fixture(
                    id: "idle-newer",
                    preview: "Idle",
                    updatedAt: 200,
                    status: .idle
                ),
                CodexThread.fixture(
                    id: "active-older",
                    preview: "Active",
                    updatedAt: 100,
                    status: .active
                ),
            ]
        )
        let model = RelayAppModel(providerFactory: { provider })

        await model.refresh()

        #expect(
            model.threads.map(\.id)
                == ["active-older", "idle-newer"]
        )
    }

    @MainActor
    @Test
    func refreshHidesTheRelayControllerFromTheWorkerList() async {
        let provider = StubThreadProvider(
            threads: [
                CodexThread.fixture(
                    id: "controller",
                    name: "Relay Controller",
                    preview: "Internal controller"
                ),
                CodexThread.fixture(
                    id: "worker",
                    name: "Research hotels",
                    preview: "Research hotels"
                ),
            ]
        )
        let model = RelayAppModel(providerFactory: { provider })

        await model.refresh()

        #expect(model.threads.map(\.id) == ["worker"])
    }

    @MainActor
    @Test
    func ignoresAnOverlappingRefresh() async {
        let provider = CountingThreadProvider()
        let model = RelayAppModel(providerFactory: { provider })

        async let first: Void = model.refresh()
        await provider.waitUntilRefreshStarts()
        await model.refresh()
        let callCount = await provider.callCount()
        await provider.finishRefresh()
        _ = await first

        #expect(callCount == 1)
    }

    @MainActor
    @Test
    func sendsCommandsThroughTheControllerAndPublishesItsAnswer() async {
        let provider = StubThreadProvider(threads: [])
        let handler = CommandHandlerStub(
            result: .success("I started a worker task.")
        )
        let model = RelayAppModel(
            providerFactory: { provider },
            commandHandler: handler
        )
        model.commandText = "  Build the command box  "

        await model.submitCommand()

        #expect(await handler.prompts() == ["Build the command box"])
        #expect(model.latestResponse == "I started a worker task.")
        #expect(model.chatMessages.map(\.role) == [.user, .relay])
        #expect(
            model.chatMessages.map(\.text)
                == [
                    "Build the command box",
                    "I started a worker task.",
                ]
        )
        #expect(model.commandText.isEmpty)
        #expect(model.composerPhase == .idle)
    }

    @MainActor
    @Test
    func exposesControllerFailuresInTheComposer() async {
        let provider = StubThreadProvider(threads: [])
        let handler = CommandHandlerStub(
            result: .failure(CommandFailure.offline)
        )
        let model = RelayAppModel(
            providerFactory: { provider },
            commandHandler: handler
        )
        model.commandText = "What is running?"

        await model.submitCommand()

        #expect(model.latestResponse == nil)
        #expect(
            model.composerPhase
                == .failed("The controller is offline.")
        )
    }

    @MainActor
    @Test
    func typedCommandPublishesStreamingAnswerBeforeCompletion() async {
        let handler = BlockingStreamingCommandHandler()
        let model = RelayAppModel(commandHandler: handler)
        model.commandText = "Status"

        let submission = Task { await model.submitCommand() }
        await handler.waitForUpdate()
        for _ in 0..<100 where model.latestResponse != "Partial answer" {
            await Task.yield()
        }

        #expect(model.latestResponse == "Partial answer")
        #expect(model.chatMessages.last?.text == "Partial answer")
        #expect(model.chatMessages.count == 2)
        #expect(model.composerPhase == .sending)

        await handler.finish()
        await submission.value
        #expect(model.latestResponse == "Partial answer completed.")
        #expect(model.chatMessages.last?.text == "Partial answer completed.")
        #expect(model.chatMessages.count == 2)
    }

    @MainActor
    @Test
    func clearedWaitingStatePermanentlyPrunesResolvingOwnership() async {
        let monitoring = AppModelMonitoringStub(
            snapshots: [
                .init(tasks: [waitingActivity()], usage: nil),
                .init(tasks: [idleActivity()], usage: nil),
                .init(tasks: [waitingActivity()], usage: nil),
            ]
        )
        let activityStore = RelayActivityStore(
            monitoring: monitoring,
            tasks: AppModelTaskOperationsStub(),
            connect: {}
        )
        await activityStore.refresh()
        let model = RelayAppModel(activityStore: activityStore)
        let resolving = RelayPendingInteraction(
            id: "resolved-request",
            threadID: "worker",
            turnID: "turn",
            kind: .approval(.init(
                title: "Approve?",
                canApprove: true,
                canDecline: true
            )),
            state: .resolving
        )

        model.receivePendingInteractions([resolving])
        model.receivePendingInteractions([])
        #expect(model.pendingInteractions.map(\.id) == ["resolved-request"])

        await activityStore.refresh()
        #expect(model.pendingInteractions.isEmpty)

        await activityStore.refresh()
        #expect(model.pendingInteractions.isEmpty)
    }
}

private actor AppModelMonitoringStub: RelayActivityMonitoring {
    nonisolated let stream = AsyncStream<RelayMonitoringEvent> { _ in }
    private var snapshots: [RelayMonitoringSnapshot]

    init(snapshots: [RelayMonitoringSnapshot]) {
        self.snapshots = snapshots
    }

    nonisolated func events() -> AsyncStream<RelayMonitoringEvent> { stream }

    func snapshot(limit: Int) throws -> RelayMonitoringSnapshot {
        snapshots.removeFirst()
    }
}

private actor AppModelTaskOperationsStub: CodexTaskOperating {
    func sendToTask(id: String, prompt: String) async throws -> CodexTaskLaunch {
        fatalError("Not used")
    }

    func interruptTask(id: String) async throws {
        fatalError("Not used")
    }
}

private func waitingActivity() -> RelayTaskActivity {
    RelayTaskActivity(
        thread: CodexThread(
            id: "worker",
            preview: "Worker",
            cwd: "/tmp",
            updatedAt: 1,
            status: .active,
            activeFlags: [.waitingOnUserInput]
        )
    )
}

private func idleActivity() -> RelayTaskActivity {
    RelayTaskActivity(
        thread: CodexThread(
            id: "worker",
            preview: "Worker",
            cwd: "/tmp",
            updatedAt: 2,
            status: .idle
        )
    )
}

private actor BlockingStreamingCommandHandler: RelayCommandHandling {
    private var didUpdate = false
    private var updateWaiters: [CheckedContinuation<Void, Never>] = []
    private var finishContinuation: CheckedContinuation<Void, Never>?

    func submit(_ text: String) async throws -> String {
        "Partial answer completed."
    }

    func submit(
        _ text: String,
        onAnswerUpdate: @escaping @Sendable (String) async -> Void
    ) async throws -> String {
        await onAnswerUpdate("Partial answer")
        didUpdate = true
        let waiters = updateWaiters
        updateWaiters.removeAll()
        for waiter in waiters { waiter.resume() }
        await withCheckedContinuation { finishContinuation = $0 }
        return "Partial answer completed."
    }

    func waitForUpdate() async {
        if didUpdate { return }
        await withCheckedContinuation { updateWaiters.append($0) }
    }

    func finish() {
        finishContinuation?.resume()
        finishContinuation = nil
    }
}

private actor StubThreadProvider: CodexThreadProviding {
    private let threads: [CodexThread]

    init(threads: [CodexThread]) {
        self.threads = threads
    }

    func loadThreads(limit: Int) async throws -> [CodexThread] {
        Array(threads.prefix(limit))
    }
}

private actor CountingThreadProvider: CodexThreadProviding {
    private var calls = 0
    private var finishContinuation: CheckedContinuation<Void, Never>?

    func loadThreads(limit: Int) async throws -> [CodexThread] {
        calls += 1
        await withCheckedContinuation { continuation in
            finishContinuation = continuation
        }
        return []
    }

    func waitUntilRefreshStarts() async {
        while calls == 0 {
            await Task.yield()
        }
    }

    func finishRefresh() {
        finishContinuation?.resume()
        finishContinuation = nil
    }

    func callCount() -> Int {
        calls
    }
}

private actor CommandHandlerStub: RelayCommandHandling {
    private let result: Result<String, any Error>
    private var recordedPrompts: [String] = []

    init(result: Result<String, any Error>) {
        self.result = result
    }

    func submit(_ text: String) async throws -> String {
        recordedPrompts.append(text)
        return try result.get()
    }

    func prompts() -> [String] {
        recordedPrompts
    }
}

private enum CommandFailure: Error, LocalizedError {
    case offline

    var errorDescription: String? {
        "The controller is offline."
    }
}

private extension CodexThread {
    static func fixture(
        id: String,
        name: String? = nil,
        preview: String,
        updatedAt: Int = 1_784_210_400,
        status: CodexThreadStatus = .idle
    ) -> CodexThread {
        CodexThread(
            id: id,
            name: name,
            preview: preview,
            cwd: "/Users/ayushrungta/Work/Relay",
            updatedAt: updatedAt,
            status: status
        )
    }
}
