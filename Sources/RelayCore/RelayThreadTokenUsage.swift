import Foundation

public struct RelayTokenUsageBreakdown: Sendable, Equatable, Codable {
    public let inputTokens: Int64
    public let cachedInputTokens: Int64
    public let outputTokens: Int64
    public let reasoningOutputTokens: Int64
    public let totalTokens: Int64

    public init(
        inputTokens: Int64,
        cachedInputTokens: Int64,
        outputTokens: Int64,
        reasoningOutputTokens: Int64,
        totalTokens: Int64
    ) {
        self.inputTokens = inputTokens
        self.cachedInputTokens = cachedInputTokens
        self.outputTokens = outputTokens
        self.reasoningOutputTokens = reasoningOutputTokens
        self.totalTokens = totalTokens
    }
}

public struct RelayThreadTokenUsage: Sendable, Equatable, Codable {
    public let total: RelayTokenUsageBreakdown
    public let last: RelayTokenUsageBreakdown
    public let modelContextWindow: Int64?

    public var contextPercentage: Double? {
        guard let modelContextWindow, modelContextWindow > 0 else {
            return nil
        }
        return Double(last.totalTokens) / Double(modelContextWindow) * 100
    }

    public init(
        total: RelayTokenUsageBreakdown,
        last: RelayTokenUsageBreakdown,
        modelContextWindow: Int64?
    ) {
        self.total = total
        self.last = last
        self.modelContextWindow = modelContextWindow
    }
}
