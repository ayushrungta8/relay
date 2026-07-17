import RelayCodexClient
import RelayCore

nonisolated struct RelayActivityReducer: Sendable {
    private var tasksByID: [String: RelayTaskActivity] = [:]

    private(set) var usage: RelayUsageSnapshot?
    private(set) var tokenUsageByThreadID:
        [String: RelayThreadTokenUsage] = [:]
    private(set) var lastSelectedThreadID: String?
    private(set) var selectedThreadID: String?

    var attentionTasks: [RelayTaskActivity] {
        orderedTasks.filter {
            switch $0.attentionState {
            case .needsInput, .failed, .ready:
                true
            case .running, .idle:
                false
            }
        }
    }

    var runningTasks: [RelayTaskActivity] {
        orderedTasks.filter { $0.attentionState == .running }
    }

    var recentTasks: [RelayTaskActivity] {
        orderedTasks.filter { $0.attentionState == .idle }
    }

    mutating func merge(
        snapshot: RelayMonitoringSnapshot,
        controllerThreadID: String? = nil
    ) {
        var merged: [String: RelayTaskActivity] = [:]
        for task in snapshot.tasks
        where !Self.isController(
            task,
            controllerThreadID: controllerThreadID
        ) {
            let previous = tasksByID[task.id]
            merged[task.id] = Self.merging(
                task,
                previous: previous
            )
        }
        tasksByID = merged
        if let selectedThreadID, merged[selectedThreadID] == nil {
            self.selectedThreadID = nil
        }
        usage = snapshot.usage
        tokenUsageByThreadID = snapshot.tokenUsageByThreadID
    }

    mutating func merge(event: RelayMonitoringEvent) {
        switch event {
        case let .threadStatusChanged(threadID, status, activeFlags):
            guard let previous = tasksByID[threadID] else { return }
            let updated = RelayTaskActivity(
                thread: CodexThread(
                    id: previous.thread.id,
                    name: previous.thread.name,
                    preview: previous.thread.preview,
                    cwd: previous.thread.cwd,
                    updatedAt: previous.thread.updatedAt,
                    status: status,
                    activeFlags: activeFlags
                ),
                latestUpdate: previous.latestUpdate,
                latestTurnStatus: previous.latestTurnStatus,
                latestTurnError: previous.latestTurnError
            )
            tasksByID[threadID] = Self.merging(
                updated,
                previous: previous
            )
        case let .threadTokenUsageUpdated(threadID, _, usage):
            tokenUsageByThreadID[threadID] = usage
        case let .usageUpdated(usage):
            self.usage = usage
        case .taskChanged, .lifecycle, .protocolIssue:
            break
        }
    }

    mutating func markRead(threadID: String) {
        select(threadID: threadID)
        guard let task = tasksByID[threadID] else { return }
        tasksByID[threadID] = RelayTaskActivity(
            thread: task.thread,
            latestUpdate: task.latestUpdate,
            hasUnreadCompletion: false,
            latestTurnStatus: task.latestTurnStatus,
            latestTurnError: task.latestTurnError
        )
    }

    mutating func select(threadID: String) {
        selectedThreadID = threadID
        lastSelectedThreadID = threadID
    }

    func contains(threadID: String) -> Bool {
        tasksByID[threadID] != nil
    }

    private var orderedTasks: [RelayTaskActivity] {
        tasksByID.values.sorted {
            if $0.attentionState.priority != $1.attentionState.priority {
                return $0.attentionState.priority
                    > $1.attentionState.priority
            }
            if $0.thread.updatedAt != $1.thread.updatedAt {
                return $0.thread.updatedAt > $1.thread.updatedAt
            }
            return $0.id < $1.id
        }
    }

    private static func merging(
        _ task: RelayTaskActivity,
        previous: RelayTaskActivity?
    ) -> RelayTaskActivity {
        let becameCompleted = previous?.thread.status == .active
            && task.thread.status == .idle
        let becameFailed = previous.map {
            $0.thread.status != .systemError
                && task.thread.status == .systemError
        } ?? false
        return RelayTaskActivity(
            thread: task.thread,
            latestUpdate: task.latestUpdate,
            hasUnreadCompletion: task.hasUnreadCompletion
                || previous?.hasUnreadCompletion == true
                || becameCompleted
                || becameFailed,
            latestTurnStatus: task.latestTurnStatus,
            latestTurnError: task.latestTurnError
        )
    }

    private static func isController(
        _ task: RelayTaskActivity,
        controllerThreadID: String?
    ) -> Bool {
        if task.id == controllerThreadID {
            return true
        }
        return task.thread.name?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .caseInsensitiveCompare("Relay Controller") == .orderedSame
    }
}

actor RelayActivityState {
    private var reducer = RelayActivityReducer()
    private var eventVersion = 0
    private var events: [(version: Int, event: RelayMonitoringEvent)] = []

    func beginSnapshot() -> Int { eventVersion }

    func merge(
        snapshot: RelayMonitoringSnapshot,
        controllerThreadID: String?,
        replayingEventsAfter version: Int
    ) -> RelayActivityValues {
        reducer.merge(
            snapshot: snapshot,
            controllerThreadID: controllerThreadID
        )
        for entry in events where entry.version > version {
            reducer.merge(event: entry.event)
        }
        events.removeAll()
        return RelayActivityValues(reducer: reducer)
    }

    func merge(event: RelayMonitoringEvent) -> RelayActivityEventMergeResult {
        eventVersion += 1
        events.append((eventVersion, event))
        let needsRefresh: Bool
        if case let .threadStatusChanged(threadID, _, _) = event {
            needsRefresh = !reducer.contains(threadID: threadID)
        } else {
            needsRefresh = false
        }
        reducer.merge(event: event)
        return RelayActivityEventMergeResult(
            values: RelayActivityValues(reducer: reducer),
            needsRefresh: needsRefresh
        )
    }

    func markRead(threadID: String) -> RelayActivityValues {
        reducer.markRead(threadID: threadID)
        return RelayActivityValues(reducer: reducer)
    }

    func select(threadID: String) -> RelayActivityValues {
        reducer.select(threadID: threadID)
        return RelayActivityValues(reducer: reducer)
    }
}

nonisolated struct RelayActivityValues: Sendable {
    let attentionTasks: [RelayTaskActivity]
    let runningTasks: [RelayTaskActivity]
    let recentTasks: [RelayTaskActivity]
    let usage: RelayUsageSnapshot?
    let tokenUsageByThreadID: [String: RelayThreadTokenUsage]
    let lastSelectedThreadID: String?
    let selectedThreadID: String?

    init(reducer: RelayActivityReducer) {
        attentionTasks = reducer.attentionTasks
        runningTasks = reducer.runningTasks
        recentTasks = reducer.recentTasks
        usage = reducer.usage
        tokenUsageByThreadID = reducer.tokenUsageByThreadID
        lastSelectedThreadID = reducer.lastSelectedThreadID
        selectedThreadID = reducer.selectedThreadID
    }
}

nonisolated struct RelayActivityEventMergeResult: Sendable {
    let values: RelayActivityValues
    let needsRefresh: Bool
}
