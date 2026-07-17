import Foundation
import Observation
import RelayBrain
import RelayCodexBridge
import RelayCodexClient
import RelayCore

nonisolated protocol RelayActivityMonitoring: Sendable {
    nonisolated func events() -> AsyncStream<RelayMonitoringEvent>
    func snapshot(limit: Int) async throws -> RelayMonitoringSnapshot
    func consumeResetCredit(
        creditID: String?
    ) async throws -> CodexResetCreditConsumeOutcome
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

    private let defaults: UserDefaults
    private static let autoApplyDefaultsKey =
        "relay.autoApplyResetCreditBeforeExpiry"
    static let autoApplyLeadTime: TimeInterval = 3_600

    private var eventTask: Task<Void, Never>?
    private var autoApplyTask: Task<Void, Never>?
    private var autoApplyAttemptedCreditIDs: Set<String> = []
    private var periodicRefreshTask: Task<Void, Never>?
    private var reconnectTask: Task<Void, Never>?
    private var isStarted = false
    private var isRefreshing = false
    private var refreshRequested = false
    private var reconnectAttempt = 0
    @ObservationIgnored
    var activityPublished: (@MainActor () -> Void)?

    private(set) var attentionTasks: [RelayTaskActivity] = []
    private(set) var runningTasks: [RelayTaskActivity] = []
    private(set) var recentTasks: [RelayTaskActivity] = []
    private(set) var usage: RelayUsageSnapshot?
    private(set) var tokenUsageByThreadID:
        [String: RelayThreadTokenUsage] = [:]
    private(set) var connectionState: RelayConnectionState = .idle
    private(set) var lastSelectedThreadID: String?
    private(set) var selectedThreadID: String?
    private(set) var lastUpdatedAt: Date?

    var autoApplyResetCredits: Bool {
        didSet {
            guard autoApplyResetCredits != oldValue else { return }
            defaults.set(
                autoApplyResetCredits,
                forKey: Self.autoApplyDefaultsKey
            )
            scheduleAutoApply()
        }
    }

    init(
        monitoring: any RelayActivityMonitoring,
        tasks: any CodexTaskOperating,
        controllerThreadStore:
            (any RelayControllerThreadStoring)? = nil,
        connect: @escaping Connect,
        sleep: @escaping Sleep = { duration in
            try await Task.sleep(for: duration)
        },
        defaults: UserDefaults = .standard
    ) {
        self.monitoring = monitoring
        self.tasks = tasks
        self.controllerThreadStore = controllerThreadStore
        self.connect = connect
        self.sleep = sleep
        self.defaults = defaults
        autoApplyResetCredits = defaults.bool(
            forKey: Self.autoApplyDefaultsKey
        )
    }

    func start() async {
        guard !isStarted else { return }
        isStarted = true
        startEventConsumption()
        startPeriodicRefresh()
        await connectAndRefresh()
    }

    func refresh() async {
        guard !isRefreshing else {
            refreshRequested = true
            return
        }
        isRefreshing = true
        defer { isRefreshing = false }

        repeat {
            refreshRequested = false
            await performRefresh()
        } while refreshRequested
    }

    func retryConnection() async {
        cancelReconnect()
        await connectAndRefresh()
    }

    private func performRefresh() async {
        let eventVersion = await state.beginSnapshot()
        do {
            let snapshot = try await monitoring.snapshot(limit: 25)
            let controllerThreadID =
                await controllerThreadStore?.loadThreadID()
            let values = await state.merge(
                snapshot: snapshot,
                controllerThreadID: controllerThreadID,
                replayingEventsAfter: eventVersion
            )
            lastUpdatedAt = .now
            publish(values)
            cancelReconnect()
            reconnectAttempt = 0
            connectionState = .connected(lastUpdatedAt: lastUpdatedAt ?? .now)
        } catch {
            connectionState = .offline(
                message: error.localizedDescription,
                reconnectAttempt: reconnectAttempt,
                lastUpdatedAt: lastUpdatedAt
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

    func applyResetCredit(
        id: String
    ) async throws -> CodexResetCreditConsumeOutcome {
        let outcome = try await monitoring.consumeResetCredit(creditID: id)
        await refresh()
        return outcome
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
        attentionTasks.map(Self.summary(for:))
    }

    func visibleTasks() async -> [RelayTaskSummary]? {
        (attentionTasks + runningTasks + recentTasks).map(Self.summary(for:))
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
                reconnectAttempt: reconnectAttempt,
                lastUpdatedAt: lastUpdatedAt
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
            let result = await state.merge(event: event)
            publish(result.values)
            if result.needsRefresh {
                await refresh()
            }
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
            connectionState = .connected(lastUpdatedAt: lastUpdatedAt ?? .now)
        case .stopping:
            break
        case let .failed(message):
            connectionState = .offline(
                message: message,
                reconnectAttempt: reconnectAttempt,
                lastUpdatedAt: lastUpdatedAt
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
        selectedThreadID = values.selectedThreadID
        activityPublished?()
        scheduleAutoApply()
    }

    private func scheduleAutoApply() {
        autoApplyTask?.cancel()
        autoApplyTask = nil
        guard autoApplyResetCredits,
              let credit = nextAutoApplyCandidate(),
              let expiresAt = credit.expiresAt else { return }
        let fireAt = Date(
            timeIntervalSince1970: TimeInterval(expiresAt)
        ).addingTimeInterval(-Self.autoApplyLeadTime)
        let delay = fireAt.timeIntervalSinceNow
        let creditID = credit.id
        autoApplyTask = Task { [weak self, sleep] in
            if delay > 0 {
                try? await sleep(.seconds(delay))
            }
            guard let self, !Task.isCancelled else { return }
            await self.performAutoApply(creditID: creditID)
        }
    }

    private func nextAutoApplyCandidate() -> RelayRateLimitResetCredit? {
        let now = Date().timeIntervalSince1970
        return usage?.resetCredits?
            .filter { credit in
                credit.status == "available"
                    && !autoApplyAttemptedCreditIDs.contains(credit.id)
                    && credit.expiresAt.map {
                        TimeInterval($0) > now
                    } == true
            }
            .min { ($0.expiresAt ?? .max) < ($1.expiresAt ?? .max) }
    }

    private func performAutoApply(creditID: String) async {
        guard autoApplyResetCredits else { return }
        autoApplyAttemptedCreditIDs.insert(creditID)
        _ = try? await monitoring.consumeResetCredit(creditID: creditID)
        await refresh()
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

    private static func summary(
        for task: RelayTaskActivity
    ) -> RelayTaskSummary {
        RelayTaskSummary(
            id: task.id,
            title: title(for: task),
            project: task.thread.cwd,
            status: status(for: task.attentionState),
            updatedAt: Date(
                timeIntervalSince1970: TimeInterval(task.thread.updatedAt)
            ),
            latestUpdate: task.latestUpdate
        )
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
        autoApplyTask?.cancel()
    }
}
