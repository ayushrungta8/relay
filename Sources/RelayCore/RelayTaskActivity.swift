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

public enum RelayTaskAttentionReason: Sendable, Equatable, Hashable {
    case structuredInteraction
    case inferredReplyRequest
    case failure
    case unreadCompletion
    case running
    case none
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
    public let latestFinalResponse: RelayTaskFinalResponse?
    public let hasInferredReplyRequest: Bool
    public let attentionReason: RelayTaskAttentionReason
    public let attentionState: RelayTaskAttentionState

    public var id: String { thread.id }

    public var inferredAttentionAction:
        RelayConversationalAttentionAction? {
        guard attentionReason == .inferredReplyRequest,
              let latestFinalResponse else { return nil }
        return RelayConversationalAttentionRules.suggestedAction(
            for: latestFinalResponse.text
        )
    }

    public init(
        thread: CodexThread,
        latestUpdate: String? = nil,
        hasUnreadCompletion: Bool = false,
        latestTurnStatus: RelayTaskTurnStatus? = nil,
        latestTurnError: String? = nil,
        latestFinalResponse: RelayTaskFinalResponse? = nil,
        hasInferredReplyRequest: Bool = false
    ) {
        self.thread = thread
        self.latestUpdate = latestUpdate
        self.hasUnreadCompletion = hasUnreadCompletion
        self.latestTurnStatus = latestTurnStatus
        self.latestTurnError = latestTurnError
        self.latestFinalResponse = latestFinalResponse
        self.hasInferredReplyRequest = hasInferredReplyRequest
        attentionReason = Self.attentionReason(
            for: thread,
            hasUnreadCompletion: hasUnreadCompletion,
            latestTurnStatus: latestTurnStatus,
            hasInferredReplyRequest: hasInferredReplyRequest
        )
        attentionState = Self.attentionState(for: attentionReason)
    }

    public func settingInferredReplyRequest(
        _ value: Bool
    ) -> RelayTaskActivity {
        RelayTaskActivity(
            thread: thread,
            latestUpdate: latestUpdate,
            hasUnreadCompletion: hasUnreadCompletion,
            latestTurnStatus: latestTurnStatus,
            latestTurnError: latestTurnError,
            latestFinalResponse: latestFinalResponse,
            hasInferredReplyRequest: value
        )
    }

    private static func attentionReason(
        for thread: CodexThread,
        hasUnreadCompletion: Bool,
        latestTurnStatus: RelayTaskTurnStatus?,
        hasInferredReplyRequest: Bool
    ) -> RelayTaskAttentionReason {
        if thread.activeFlags.contains(.waitingOnApproval)
            || thread.activeFlags.contains(.waitingOnUserInput) {
            return .structuredInteraction
        }
        if hasInferredReplyRequest {
            return .inferredReplyRequest
        }
        if thread.status == .systemError || latestTurnStatus == .failed {
            return .failure
        }
        if hasUnreadCompletion {
            return .unreadCompletion
        }
        if thread.status == .active {
            return .running
        }
        return .none
    }

    private static func attentionState(
        for reason: RelayTaskAttentionReason
    ) -> RelayTaskAttentionState {
        switch reason {
        case .structuredInteraction, .inferredReplyRequest:
            .needsInput
        case .failure:
            .failed
        case .unreadCompletion:
            .ready
        case .running:
            .running
        case .none:
            .idle
        }
    }
}
