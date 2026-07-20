import Foundation

public struct RelayPendingRequestSummary: Sendable, Equatable, Encodable {
    public let kind: String
    public let prompt: String

    public init(kind: String, prompt: String) {
        self.kind = kind
        self.prompt = prompt
    }
}

public struct RelayTaskSummary: Sendable, Equatable, Encodable {
    public let id: String
    public let title: String
    public let project: String
    public let status: String
    public let updatedAt: Date
    public let latestUpdate: String?
    public let pendingRequests: [RelayPendingRequestSummary]

    public init(
        id: String,
        title: String,
        project: String,
        status: String,
        updatedAt: Date,
        latestUpdate: String? = nil,
        pendingRequests: [RelayPendingRequestSummary] = []
    ) {
        self.id = id
        self.title = title
        self.project = project
        self.status = status
        self.updatedAt = updatedAt
        self.latestUpdate = latestUpdate
        self.pendingRequests = pendingRequests
    }

    private enum CodingKeys: String, CodingKey {
        case id
        case title
        case project
        case status
        case updatedAt
        case latestUpdate
        case pendingRequests
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(title, forKey: .title)
        try container.encode(project, forKey: .project)
        try container.encode(status, forKey: .status)
        try container.encode(updatedAt, forKey: .updatedAt)
        try container.encodeIfPresent(latestUpdate, forKey: .latestUpdate)
        if !pendingRequests.isEmpty {
            try container.encode(pendingRequests, forKey: .pendingRequests)
        }
    }
}

public protocol RelayTaskOperations: Sendable {
    func listTasks() async throws -> [RelayTaskSummary]
    func getTask(id: String) async throws -> RelayTaskSummary?
    func startTask(prompt: String, cwd: String?) async throws -> RelayTaskSummary
    func interruptTask(id: String) async throws
}

public struct RelayControllerUsageWindow: Sendable, Equatable, Encodable {
    public let usedPercent: Int
    public let windowDurationMinutes: Int64?
    public let resetsAt: Int64?

    public init(
        usedPercent: Int,
        windowDurationMinutes: Int64?,
        resetsAt: Int64?
    ) {
        self.usedPercent = usedPercent
        self.windowDurationMinutes = windowDurationMinutes
        self.resetsAt = resetsAt
    }
}

public struct RelayControllerUsage: Sendable, Equatable, Encodable {
    public let limitID: String?
    public let limitName: String?
    public let primary: RelayControllerUsageWindow?
    public let secondary: RelayControllerUsageWindow?
    public let resetCreditsAvailableCount: Int64?

    public init(
        limitID: String? = nil,
        limitName: String? = nil,
        primary: RelayControllerUsageWindow?,
        secondary: RelayControllerUsageWindow?,
        resetCreditsAvailableCount: Int64? = nil
    ) {
        self.limitID = limitID
        self.limitName = limitName
        self.primary = primary
        self.secondary = secondary
        self.resetCreditsAvailableCount = resetCreditsAvailableCount
    }

    private enum CodingKeys: String, CodingKey {
        case limitID
        case limitName
        case primary
        case secondary
        case resetCreditsAvailableCount
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encodeIfPresent(limitID, forKey: .limitID)
        try container.encodeIfPresent(limitName, forKey: .limitName)
        if let primary {
            try container.encode(primary, forKey: .primary)
        } else {
            try container.encodeNil(forKey: .primary)
        }
        if let secondary {
            try container.encode(secondary, forKey: .secondary)
        } else {
            try container.encodeNil(forKey: .secondary)
        }
        try container.encodeIfPresent(
            resetCreditsAvailableCount,
            forKey: .resetCreditsAvailableCount
        )
    }
}

public struct RelayTaskReferenceContext: Sendable, Equatable {
    public let selectedTaskID: String?
    public let lastInteractedTaskID: String?

    public init(
        selectedTaskID: String? = nil,
        lastInteractedTaskID: String? = nil
    ) {
        self.selectedTaskID = selectedTaskID
        self.lastInteractedTaskID = lastInteractedTaskID
    }

    public var resolvedTaskID: String? {
        selectedTaskID ?? lastInteractedTaskID
    }
}

public protocol RelaySupervisionStateReading: Sendable {
    func visibleTasks() async -> [RelayTaskSummary]?
    func attentionInbox() async -> [RelayTaskSummary]
    func currentUsage() async -> RelayControllerUsage?
    func taskReferenceContext() async -> RelayTaskReferenceContext
}

public extension RelaySupervisionStateReading {
    func visibleTasks() async -> [RelayTaskSummary]? { nil }
}
