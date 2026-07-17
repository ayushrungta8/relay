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

public enum RelayTaskTurnStatus: Codable, Sendable, Equatable {
    case completed
    case failed
    case interrupted
    case inProgress
    case unknown(String)

    public init(from decoder: any Decoder) throws {
        let value = try decoder.singleValueContainer().decode(String.self)
        self = switch value {
        case "completed": .completed
        case "failed": .failed
        case "interrupted": .interrupted
        case "inProgress": .inProgress
        default: .unknown(value)
        }
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.singleValueContainer()
        let value = switch self {
        case .completed: "completed"
        case .failed: "failed"
        case .interrupted: "interrupted"
        case .inProgress: "inProgress"
        case let .unknown(value): value
        }
        try container.encode(value)
    }
}

public struct RelayTaskActivity: Sendable, Equatable, Identifiable {
    public let thread: CodexThread
    public let latestUpdate: String?
    public let hasUnreadCompletion: Bool
    public let latestTurnStatus: RelayTaskTurnStatus?
    public let latestTurnError: String?
    public let attentionState: RelayTaskAttentionState

    public var id: String { thread.id }

    public init(
        thread: CodexThread,
        latestUpdate: String? = nil,
        hasUnreadCompletion: Bool = false,
        latestTurnStatus: RelayTaskTurnStatus? = nil,
        latestTurnError: String? = nil
    ) {
        self.thread = thread
        self.latestUpdate = latestUpdate
        self.hasUnreadCompletion = hasUnreadCompletion
        self.latestTurnStatus = latestTurnStatus
        self.latestTurnError = latestTurnError
        attentionState = Self.attentionState(
            for: thread,
            hasUnreadCompletion: hasUnreadCompletion,
            latestTurnStatus: latestTurnStatus
        )
    }

    private static func attentionState(
        for thread: CodexThread,
        hasUnreadCompletion: Bool,
        latestTurnStatus: RelayTaskTurnStatus?
    ) -> RelayTaskAttentionState {
        if thread.activeFlags.contains(.waitingOnApproval)
            || thread.activeFlags.contains(.waitingOnUserInput) {
            return .needsInput
        }
        if thread.status == .systemError || latestTurnStatus == .failed {
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
