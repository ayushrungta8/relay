import Foundation

public struct RelayRateLimitWindow: Sendable, Equatable, Codable {
    public let usedPercent: Int
    public let windowDurationMins: Int64?
    public let resetsAt: Int64?

    public init(
        usedPercent: Int,
        windowDurationMins: Int64?,
        resetsAt: Int64?
    ) {
        self.usedPercent = usedPercent
        self.windowDurationMins = windowDurationMins
        self.resetsAt = resetsAt
    }
}

public struct RelayRateLimitResetCredit: Sendable, Equatable, Codable {
    public let id: String
    public let title: String?
    public let description: String?
    public let grantedAt: Int64
    public let expiresAt: Int64?
    public let resetType: String
    public let status: String

    public init(
        id: String,
        title: String?,
        description: String?,
        grantedAt: Int64,
        expiresAt: Int64?,
        resetType: String,
        status: String
    ) {
        self.id = id
        self.title = title
        self.description = description
        self.grantedAt = grantedAt
        self.expiresAt = expiresAt
        self.resetType = resetType
        self.status = status
    }
}

public struct RelayUsageSnapshot: Sendable, Equatable {
    public let limitID: String?
    public let limitName: String?
    public let primary: RelayRateLimitWindow?
    public let secondary: RelayRateLimitWindow?
    public let resetCreditsAvailableCount: Int64?
    public let resetCredits: [RelayRateLimitResetCredit]?

    public init(
        limitID: String? = nil,
        limitName: String? = nil,
        primary: RelayRateLimitWindow?,
        secondary: RelayRateLimitWindow?,
        resetCreditsAvailableCount: Int64? = nil,
        resetCredits: [RelayRateLimitResetCredit]? = nil
    ) {
        self.limitID = limitID
        self.limitName = limitName
        self.primary = primary
        self.secondary = secondary
        self.resetCreditsAvailableCount = resetCreditsAvailableCount
        self.resetCredits = resetCredits
    }
}
