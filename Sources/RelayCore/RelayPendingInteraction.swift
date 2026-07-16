import Foundation

public struct RelayPendingInteraction: Sendable, Equatable, Identifiable {
    public let id: String
    public let threadID: String
    public let turnID: String?
    public let kind: RelayPendingInteractionKind

    public init(
        id: String,
        threadID: String,
        turnID: String?,
        kind: RelayPendingInteractionKind
    ) {
        self.id = id
        self.threadID = threadID
        self.turnID = turnID
        self.kind = kind
    }
}

public enum RelayPendingInteractionKind: Sendable, Equatable {
    case questions([RelayPendingQuestion])
    case approval(RelayPendingApproval)
}

public struct RelayPendingQuestion: Sendable, Equatable, Identifiable {
    public let id: String
    public let header: String
    public let question: String
    public let options: [RelayPendingQuestionOption]
    public let allowsOther: Bool
    public let isSecret: Bool

    public init(
        id: String,
        header: String,
        question: String,
        options: [RelayPendingQuestionOption] = [],
        allowsOther: Bool = false,
        isSecret: Bool = false
    ) {
        self.id = id
        self.header = header
        self.question = question
        self.options = options
        self.allowsOther = allowsOther
        self.isSecret = isSecret
    }
}

public struct RelayPendingQuestionOption: Sendable, Equatable {
    public let label: String
    public let description: String

    public init(label: String, description: String) {
        self.label = label
        self.description = description
    }
}

public struct RelayPendingApproval: Sendable, Equatable {
    public let title: String
    public let detail: String?
    public let canApprove: Bool
    public let canDecline: Bool

    public init(
        title: String,
        detail: String? = nil,
        canApprove: Bool,
        canDecline: Bool
    ) {
        self.title = title
        self.detail = detail
        self.canApprove = canApprove
        self.canDecline = canDecline
    }
}

public enum RelayPendingApprovalDecision: Sendable, Equatable {
    case approve
    case decline
}
