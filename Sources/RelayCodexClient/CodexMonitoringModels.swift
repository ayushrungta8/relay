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
            if let message = turn.items.reversed().first(where: {
                $0.type == "agentMessage" && !($0.text ?? "").isEmpty
            })?.text {
                return Self.normalized(message)
            }
            if let plan = turn.items.reversed().first(where: {
                $0.type == "plan" && !($0.text ?? "").isEmpty
            })?.text {
                return Self.normalized(plan)
            }
            if let command = turn.items.reversed().first(where: {
                $0.type == "commandExecution"
                    && !($0.command ?? "").isEmpty
            }) {
                let prefix = command.status == "inProgress"
                    ? "Running"
                    : "Last command"
                return Self.normalized(
                    "\(prefix): \(command.command ?? "")"
                )
            }
            if let error = turn.error?.message, !error.isEmpty {
                return Self.normalized("Failed: \(error)")
            }
        }
        return nil
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
