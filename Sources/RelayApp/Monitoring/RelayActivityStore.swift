import Foundation
import Observation
import RelayBrain
import RelayCodexBridge
import RelayCodexClient
import RelayCore

nonisolated protocol RelayActivityMonitoring: Sendable {
    nonisolated func events() -> AsyncStream<RelayMonitoringEvent>
    func snapshot(limit: Int) async throws -> RelayMonitoringSnapshot
}

extension CodexMonitoringClient: RelayActivityMonitoring {}

@MainActor
@Observable
final class RelayActivityStore: RelaySupervisionStateReading {
    typealias Connect = @Sendable () async throws -> Void
    typealias Sleep = @Sendable (Duration) async throws -> Void

    private let monitoring: any RelayActivityMonitoring
    private let tasks: any CodexTaskOperating
    private let controllerThreadStore:
        (any RelayControllerThreadStoring)?
    private let connect: Connect
    private let sleep: Sleep
    private let state = RelayActivityState()

    private var eventTask: Task<Void, Never>?
    private var periodicRefreshTask: Task<Void, Never>?
    private var reconnectTask: Task<Void, Never>?
    private var isStarted = false
    private var isRefreshing = false
    private var reconnectAttempt = 0

    private(set) var attentionTasks: [RelayTaskActivity] = []
    private(set) var runningTasks: [RelayTaskActivity] = []
    private(set) var recentTasks: [RelayTaskActivity] = []
    private(set) var usage: RelayUsageSnapshot?
    private(set) var tokenUsageByThreadID:
        [String: RelayThreadTokenUsage] = [:]
    private(set) var connectionState: RelayConnectionState = .idle
    private(set) var lastSelectedThreadID: String?
    private(set) var selectedThreadID: String?

    init(
        monitoring: any RelayActivityMonitoring,
        tasks: any CodexTaskOperating,
        controllerThreadStore:
            (any RelayControllerThreadStoring)? = nil,
        connect: @escaping Connect,
        sleep: @escaping Sleep = { duration in
            try await Task.sleep(for: duration)
        }
    ) {
        self.monitoring = monitoring
        self.tasks = tasks
        self.controllerThreadStore = controllerThreadStore
        self.connect = connect
        self.sleep = sleep
    }

    func start() async {
        guard !isStarted else { return }
        isStarted = true
        startEventConsumption()
        startPeriodicRefresh()
        await connectAndRefresh()
    }

    func refresh() async {
        guard !isRefreshing else { return }
        isRefreshing = true
        defer { isRefreshing = false }

        do {
            let snapshot = try await monitoring.snapshot(limit: 25)
            let controllerThreadID =
                await controllerThreadStore?.loadThreadID()
            publish(
                await state.merge(
                    snapshot: snapshot,
                    controllerThreadID: controllerThreadID
                )
            )
            cancelReconnect()
            reconnectAttempt = 0
            connectionState = .connected(lastUpdatedAt: Date())
        } catch {
            connectionState = .offline(
                message: error.localizedDescription,
                reconnectAttempt: reconnectAttempt
            )
            scheduleReconnect()
        }
    }

    func markRead(threadID: String) async {
        selectedThreadID = threadID
        publish(await state.markRead(threadID: threadID))
    }

    func select(threadID: String) async {
        selectedThreadID = threadID
        publish(await state.select(threadID: threadID))
    }

    func send(
        threadID: String,
        prompt: String
    ) async throws {
        let prompt = prompt.trimmingCharacters(
            in: .whitespacesAndNewlines
        )
        guard !prompt.isEmpty else {
            throw CodexTaskOperationsError.emptyPrompt
        }
        selectedThreadID = threadID
        publish(await state.markRead(threadID: threadID))
        _ = try await tasks.sendToTask(id: threadID, prompt: prompt)
        await refresh()
    }

    func interrupt(threadID: String) async throws {
        selectedThreadID = threadID
        publish(await state.select(threadID: threadID))
        try await tasks.interruptTask(id: threadID)
        await refresh()
    }

    nonisolated static func reconnectDelay(
        forAttempt attempt: Int
    ) -> Duration {
        let exponent = min(max(attempt, 0), 5)
        return .seconds(min(1 << exponent, 30))
    }

    func attentionInbox() async -> [RelayTaskSummary] {
        attentionTasks.map { task in
            RelayTaskSummary(
                id: task.id,
                title: Self.title(for: task),
                project: task.thread.cwd,
                status: Self.status(for: task.attentionState),
                updatedAt: Date(
                    timeIntervalSince1970:
                        TimeInterval(task.thread.updatedAt)
                ),
                latestUpdate: task.latestUpdate
            )
        }
    }

    func currentUsage() async -> RelayControllerUsage? {
        guard let usage else { return nil }
        return RelayControllerUsage(
            limitID: usage.limitID,
            limitName: usage.limitName,
            primary: Self.controllerWindow(usage.primary),
            secondary: Self.controllerWindow(usage.secondary),
            resetCreditsAvailableCount:
                usage.resetCreditsAvailableCount
        )
    }

    func taskReferenceContext() async -> RelayTaskReferenceContext {
        RelayTaskReferenceContext(
            selectedTaskID: selectedThreadID,
            lastInteractedTaskID: lastSelectedThreadID
        )
    }

    private func connectAndRefresh() async {
        connectionState = .connecting
        do {
            try await connect()
            await refresh()
        } catch {
            connectionState = .offline(
                message: error.localizedDescription,
                reconnectAttempt: reconnectAttempt
            )
            scheduleReconnect()
        }
    }

    private func startEventConsumption() {
        let events = monitoring.events()
        eventTask = Task { [weak self] in
            for await event in events {
                guard let self, !Task.isCancelled else { return }
                await self.receive(event)
            }
        }
    }

    private func startPeriodicRefresh() {
        periodicRefreshTask = Task { [weak self, sleep] in
            while !Task.isCancelled {
                do {
                    try await sleep(.seconds(30))
                } catch {
                    return
                }
                guard let self, !Task.isCancelled else { return }
                if self.connectionState.isConnected {
                    await self.refresh()
                }
            }
        }
    }

    private func receive(_ event: RelayMonitoringEvent) async {
        switch event {
        case .taskChanged:
            await refresh()
        case .threadStatusChanged,
             .threadTokenUsageUpdated,
             .usageUpdated:
            publish(await state.merge(event: event))
        case let .lifecycle(lifecycle):
            receive(lifecycle: lifecycle)
        case .protocolIssue:
            break
        }
    }

    private func receive(lifecycle: PersistentCodexClientState) {
        switch lifecycle {
        case .idle, .stopped:
            connectionState = .idle
        case .starting:
            connectionState = .connecting
        case .ready:
            reconnectAttempt = 0
            connectionState = .connected(lastUpdatedAt: Date())
        case .stopping:
            break
        case let .failed(message):
            connectionState = .offline(
                message: message,
                reconnectAttempt: reconnectAttempt
            )
            scheduleReconnect()
        }
    }

    private func scheduleReconnect() {
        guard isStarted, reconnectTask == nil else { return }
        let attempt = reconnectAttempt
        reconnectAttempt += 1
        reconnectTask = Task { [weak self, sleep] in
            do {
                try await sleep(Self.reconnectDelay(forAttempt: attempt))
            } catch {
                return
            }
            guard let self, !Task.isCancelled else { return }
            self.reconnectTask = nil
            await self.connectAndRefresh()
        }
    }

    private func cancelReconnect() {
        reconnectTask?.cancel()
        reconnectTask = nil
    }

    private func publish(_ values: RelayActivityValues) {
        attentionTasks = values.attentionTasks
        runningTasks = values.runningTasks
        recentTasks = values.recentTasks
        usage = values.usage
        tokenUsageByThreadID = values.tokenUsageByThreadID
        lastSelectedThreadID = values.lastSelectedThreadID
    }

    private static func title(for task: RelayTaskActivity) -> String {
        let name = task.thread.name?.trimmingCharacters(
            in: .whitespacesAndNewlines
        )
        if let name, !name.isEmpty { return name }
        let preview = task.thread.preview.trimmingCharacters(
            in: .whitespacesAndNewlines
        )
        return preview.isEmpty ? "Untitled Codex task" : preview
    }

    private static func status(
        for state: RelayTaskAttentionState
    ) -> String {
        switch state {
        case .needsInput: "needsInput"
        case .failed: "failed"
        case .ready: "ready"
        case .running: "running"
        case .idle: "idle"
        }
    }

    private static func controllerWindow(
        _ window: RelayRateLimitWindow?
    ) -> RelayControllerUsageWindow? {
        guard let window else { return nil }
        return RelayControllerUsageWindow(
            usedPercent: window.usedPercent,
            windowDurationMinutes: window.windowDurationMins,
            resetsAt: window.resetsAt
        )
    }

    isolated deinit {
        eventTask?.cancel()
        periodicRefreshTask?.cancel()
        reconnectTask?.cancel()
    }
}
