import Foundation

public enum RelayTaskAttentionState: Sendable, Equatable, Hashable {
    case needsInput
    case failed
    case ready
    case running
    case idle

    public var priority: Int {
        switch self {
        case .needsInput:
            5
        case .failed:
            4
        case .ready:
            3
        case .running:
            2
        case .idle:
            1
        }
    }
}

public struct RelayTaskActivity: Sendable, Equatable, Identifiable {
    public let thread: CodexThread
    public let latestUpdate: String?
    public let hasUnreadCompletion: Bool
    public let attentionState: RelayTaskAttentionState

    public var id: String { thread.id }

    public init(
        thread: CodexThread,
        latestUpdate: String? = nil,
        hasUnreadCompletion: Bool = false
    ) {
        self.thread = thread
        self.latestUpdate = latestUpdate
        self.hasUnreadCompletion = hasUnreadCompletion
        attentionState = Self.attentionState(
            for: thread,
            hasUnreadCompletion: hasUnreadCompletion
        )
    }

    private static func attentionState(
        for thread: CodexThread,
        hasUnreadCompletion: Bool
    ) -> RelayTaskAttentionState {
        if thread.activeFlags.contains(.waitingOnApproval)
            || thread.activeFlags.contains(.waitingOnUserInput) {
            return .needsInput
        }
        if thread.status == .systemError {
            return .failed
        }
        if hasUnreadCompletion {
            return .ready
        }
        if thread.status == .active {
            return .running
        }
        return .idle
    }
}
