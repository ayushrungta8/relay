import Foundation
import RelayCore

struct RelayActivityPresentation {
    let attentionTasks: [RelayTaskActivity]
    let runningTasks: [RelayTaskActivity]
    let recentTasks: [RelayTaskActivity]

    var orderedTasks: [RelayTaskActivity] {
        attentionTasks + runningTasks + recentTasks
    }

    var automaticPeekTrigger: RelayAutomaticPeekTrigger? {
        guard let task = attentionTasks.first else { return nil }
        return RelayAutomaticPeekTrigger(
            threadID: task.id,
            state: task.attentionState,
            updatedAt: task.thread.updatedAt,
            hasUnreadCompletion: task.hasUnreadCompletion
        )
    }

    var peekCopy: String {
        if attentionTasks.count > 1 {
            return "\(attentionTasks.count) tasks need attention"
        }
        if let task = attentionTasks.first {
            return switch task.attentionState {
            case .needsInput:
                "\(Self.title(for: task)) needs input"
            case .failed:
                "\(Self.title(for: task)) failed"
            case .ready:
                "\(Self.title(for: task)) is ready"
            case .running, .idle:
                "\(Self.title(for: task)) needs attention"
            }
        }
        if runningTasks.count > 1 {
            return "\(runningTasks.count) tasks running"
        }
        if let task = runningTasks.first {
            return "\(Self.title(for: task)) is running"
        }
        return recentTasks.isEmpty ? "Relay is quiet" : "All tasks are settled"
    }

    var expandedSummaryCopy: String {
        switch attentionTasks.count {
        case 1:
            return "1 task needs attention"
        case 2...:
            return "\(attentionTasks.count) tasks need attention"
        default:
            break
        }
        switch runningTasks.count {
        case 1:
            return "1 task running"
        case 2...:
            return "\(runningTasks.count) tasks running"
        default:
            return "Up to date"
        }
    }

    init(tasks: [RelayTaskActivity]) {
        let orderedTasks = tasks.sorted(by: Self.taskComesBefore)
        attentionTasks = orderedTasks.filter {
            switch $0.attentionState {
            case .needsInput, .failed, .ready:
                true
            case .running, .idle:
                false
            }
        }
        runningTasks = orderedTasks.filter {
            $0.attentionState == .running
        }
        recentTasks = orderedTasks.filter {
            $0.attentionState == .idle
        }
    }

    init(
        attentionTasks: [RelayTaskActivity],
        runningTasks: [RelayTaskActivity],
        recentTasks: [RelayTaskActivity]
    ) {
        self.attentionTasks = attentionTasks
        self.runningTasks = runningTasks
        self.recentTasks = recentTasks
    }

    static func title(for task: RelayTaskActivity) -> String {
        let name = task.thread.name?.trimmingCharacters(
            in: .whitespacesAndNewlines
        )
        if let name, !name.isEmpty {
            return name
        }
        let preview = task.thread.preview.trimmingCharacters(
            in: .whitespacesAndNewlines
        )
        return preview.isEmpty ? "Untitled Codex task" : preview
    }

    private static func taskComesBefore(
        _ lhs: RelayTaskActivity,
        _ rhs: RelayTaskActivity
    ) -> Bool {
        if lhs.attentionState.priority != rhs.attentionState.priority {
            return lhs.attentionState.priority > rhs.attentionState.priority
        }
        if lhs.thread.updatedAt != rhs.thread.updatedAt {
            return lhs.thread.updatedAt > rhs.thread.updatedAt
        }
        return lhs.id < rhs.id
    }
}
