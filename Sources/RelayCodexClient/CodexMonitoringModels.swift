import Foundation
import RelayCore

public struct RelayMonitoringSnapshot: Sendable, Equatable {
    public let tasks: [RelayTaskActivity]
    public let usage: RelayUsageSnapshot?
    public let tokenUsageByThreadID: [String: RelayThreadTokenUsage]

    public init(
        tasks: [RelayTaskActivity],
        usage: RelayUsageSnapshot?,
        tokenUsageByThreadID: [String: RelayThreadTokenUsage] = [:]
    ) {
        self.tasks = tasks
        self.usage = usage
        self.tokenUsageByThreadID = tokenUsageByThreadID
    }
}

public enum RelayMonitoringEvent: Sendable, Equatable {
    case threadStatusChanged(
        threadID: String,
        status: CodexThreadStatus,
        activeFlags: [CodexThreadActiveFlag]
    )
    case threadTokenUsageUpdated(
        threadID: String,
        turnID: String,
        usage: RelayThreadTokenUsage
    )
    case usageUpdated(RelayUsageSnapshot)
    case taskChanged(threadID: String)
    case lifecycle(PersistentCodexClientState)
    case protocolIssue(String)

    public var usage: RelayUsageSnapshot? {
        guard case let .usageUpdated(usage) = self else { return nil }
        return usage
    }
}

struct CodexMonitoringThreadListResult: Decodable {
    let data: [CodexMonitoringThreadRecord]
}

struct CodexMonitoringThreadReadResult: Decodable {
    let thread: CodexMonitoringThreadRecord
}

struct CodexMonitoringThreadRecord: Decodable {
    let id: String
    let name: String?
    let preview: String
    let cwd: String
    let path: String?
    let updatedAt: Int
    let status: CodexMonitoringStatusRecord
    let turns: [CodexMonitoringTurnRecord]

    var thread: CodexThread {
        CodexThread(
            id: id,
            name: name,
            preview: preview,
            cwd: cwd,
            updatedAt: updatedAt,
            status: status.type,
            activeFlags: status.activeFlags
        )
    }

    var latestUpdate: String? {
        for turn in turns.reversed() {
            if turn.status == .failed,
               let error = turn.error?.message,
               !error.isEmpty {
                return Self.normalized("Failed: \(error)")
            }
            for item in turn.items.reversed() {
                switch item.type {
                case "agentMessage":
                    if let text = item.text, !text.isEmpty {
                        return Self.normalized(text)
                    }
                case "plan":
                    if let text = item.text, !text.isEmpty {
                        return Self.normalized(text)
                    }
                case "commandExecution":
                    if let command = item.command, !command.isEmpty {
                        let prefix = item.status == "inProgress"
                            ? "Running"
                            : "Last command"
                        return Self.normalized("\(prefix): \(command)")
                    }
                default:
                    continue
                }
            }
            if let error = turn.error?.message, !error.isEmpty {
                return Self.normalized("Failed: \(error)")
            }
        }
        return nil
    }

    var latestTurnStatus: RelayTaskTurnStatus? { turns.last?.status }
    var latestTurnError: String? { turns.last?.error?.message }

    var activity: RelayTaskActivity {
        activity(sessionSnapshot: nil)
    }

    func activity(
        sessionSnapshot: CodexSessionLogSnapshot?
    ) -> RelayTaskActivity {
        let isRunning = sessionSnapshot?.isRunning == true
        let effectiveThread = if isRunning {
            CodexThread(
                id: thread.id,
                name: thread.name,
                preview: thread.preview,
                cwd: thread.cwd,
                updatedAt: thread.updatedAt,
                status: .active,
                activeFlags: thread.activeFlags
            )
        } else {
            thread
        }
        return RelayTaskActivity(
            thread: effectiveThread,
            latestUpdate: latestUpdate,
            latestTurnStatus: isRunning ? .inProgress : latestTurnStatus,
            latestTurnError: latestTurnError
        )
    }

    private static func normalized(_ text: String) -> String {
        let normalized = text.trimmingCharacters(
            in: .whitespacesAndNewlines
        )
        guard normalized.count > 800 else { return normalized }
        return String(normalized.prefix(800)) + "…"
    }
}

struct CodexMonitoringStatusRecord: Decodable {
    let type: CodexThreadStatus
    let activeFlags: [CodexThreadActiveFlag]

    private enum CodingKeys: String, CodingKey {
        case type
        case activeFlags
    }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        type = try container.decode(CodexThreadStatus.self, forKey: .type)
        activeFlags = try container.decodeIfPresent(
            [CodexThreadActiveFlag].self,
            forKey: .activeFlags
        ) ?? []
    }
}

struct CodexMonitoringTurnRecord: Decodable {
    let status: RelayTaskTurnStatus?
    let items: [CodexMonitoringItemRecord]
    let error: CodexMonitoringErrorRecord?
}

struct CodexMonitoringItemRecord: Decodable {
    let type: String
    let text: String?
    let command: String?
    let status: String?
}

struct CodexMonitoringErrorRecord: Decodable {
    let message: String
}

struct CodexRateLimitsReadResult: Decodable {
    let rateLimits: CodexRateLimitSnapshot
    let rateLimitResetCredits: CodexResetCreditSummary?

    var relaySnapshot: RelayUsageSnapshot {
        rateLimits.relaySnapshot(
            resetCreditSummary: rateLimitResetCredits
        )
    }
}

struct CodexRateLimitsUpdatedParameters: Decodable {
    let rateLimits: CodexRateLimitSnapshot
}

struct CodexRateLimitSnapshot: Decodable {
    let limitID: String?
    let limitName: String?
    let primary: RelayRateLimitWindow?
    let secondary: RelayRateLimitWindow?

    private enum CodingKeys: String, CodingKey {
        case limitID = "limitId"
        case limitName
        case primary
        case secondary
    }

    func relaySnapshot(
        resetCreditSummary: CodexResetCreditSummary? = nil
    ) -> RelayUsageSnapshot {
        RelayUsageSnapshot(
            limitID: limitID,
            limitName: limitName,
            primary: primary,
            secondary: secondary,
            resetCreditsAvailableCount: resetCreditSummary?.availableCount,
            resetCredits: resetCreditSummary?.credits
        )
    }
}

public enum CodexResetCreditConsumeOutcome: Sendable, Equatable {
    case redeemed
    case noCredit
    case alreadyRedeemed
    case unrecognized(String)

    init(rawOutcome: String) {
        switch rawOutcome {
        case "redeemed": self = .redeemed
        case "noCredit": self = .noCredit
        case "alreadyRedeemed": self = .alreadyRedeemed
        default: self = .unrecognized(rawOutcome)
        }
    }
}

struct CodexResetCreditConsumeResult: Decodable {
    let outcome: String
}

struct CodexResetCreditSummary: Decodable {
    let availableCount: Int64
    let credits: [RelayRateLimitResetCredit]?
}

struct CodexStatusChangedParameters: Decodable {
    let threadID: String
    let status: CodexMonitoringStatusRecord

    private enum CodingKeys: String, CodingKey {
        case threadID = "threadId"
        case status
    }
}

struct CodexTokenUsageUpdatedParameters: Decodable {
    let threadID: String
    let turnID: String
    let tokenUsage: RelayThreadTokenUsage

    private enum CodingKeys: String, CodingKey {
        case threadID = "threadId"
        case turnID = "turnId"
        case tokenUsage
    }
}

extension RelayUsageSnapshot {
    func mergingSparseUpdate(
        _ update: RelayUsageSnapshot
    ) -> RelayUsageSnapshot {
        RelayUsageSnapshot(
            limitID: update.limitID ?? limitID,
            limitName: update.limitName ?? limitName,
            primary: primary.mergingSparseUpdate(update.primary),
            secondary: secondary.mergingSparseUpdate(update.secondary),
            resetCreditsAvailableCount: update.resetCreditsAvailableCount
                ?? resetCreditsAvailableCount,
            resetCredits: update.resetCredits ?? resetCredits
        )
    }
}

private extension Optional where Wrapped == RelayRateLimitWindow {
    func mergingSparseUpdate(
        _ update: RelayRateLimitWindow?
    ) -> RelayRateLimitWindow? {
        guard let update else { return self }
        guard let current = self else { return update }
        return RelayRateLimitWindow(
            usedPercent: update.usedPercent,
            windowDurationMins: update.windowDurationMins
                ?? current.windowDurationMins,
            resetsAt: update.resetsAt ?? current.resetsAt
        )
    }
}
