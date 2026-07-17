import Foundation
import RelayCore

struct CodexSessionLogSnapshot: Sendable, Equatable {
    var isRunning = false
    var activeTurnID: String?
    var tokenUsage: RelayThreadTokenUsage?
    var usage: RelayUsageSnapshot?

    static func read(from url: URL) throws -> Self {
        let data = try Data(contentsOf: url, options: .mappedIfSafe)
        var snapshot = Self()

        for line in data.split(separator: 0x0A) where !line.isEmpty {
            guard let event = try? JSONDecoder().decode(
                SessionEvent.self,
                from: Data(line)
            ), event.type == "event_msg" else {
                continue
            }
            switch event.payload.type {
            case "task_started":
                snapshot.isRunning = true
                snapshot.activeTurnID = event.payload.turnID
            case "task_complete", "turn_aborted":
                snapshot.isRunning = false
                snapshot.activeTurnID = nil
            case "token_count":
                if let info = event.payload.info {
                    snapshot.tokenUsage = info.relayUsage
                }
                if let rateLimits = event.payload.rateLimits {
                    snapshot.usage = rateLimits.relaySnapshot
                }
            default:
                continue
            }
        }
        return snapshot
    }
}

private struct SessionEvent: Decodable {
    let type: String
    let payload: Payload

    struct Payload: Decodable {
        let type: String
        let info: TokenInfo?
        let rateLimits: RateLimits?
        let turnID: String?

        private enum CodingKeys: String, CodingKey {
            case type
            case info
            case rateLimits = "rate_limits"
            case turnID = "turn_id"
        }
    }
}

private struct TokenInfo: Decodable {
    let total: TokenBreakdown
    let last: TokenBreakdown
    let modelContextWindow: Int64?

    private enum CodingKeys: String, CodingKey {
        case total = "total_token_usage"
        case last = "last_token_usage"
        case modelContextWindow = "model_context_window"
    }

    var relayUsage: RelayThreadTokenUsage {
        RelayThreadTokenUsage(
            total: total.relayBreakdown,
            last: last.relayBreakdown,
            modelContextWindow: modelContextWindow
        )
    }
}

private struct TokenBreakdown: Decodable {
    let inputTokens: Int64
    let cachedInputTokens: Int64
    let outputTokens: Int64
    let reasoningOutputTokens: Int64
    let totalTokens: Int64

    private enum CodingKeys: String, CodingKey {
        case inputTokens = "input_tokens"
        case cachedInputTokens = "cached_input_tokens"
        case outputTokens = "output_tokens"
        case reasoningOutputTokens = "reasoning_output_tokens"
        case totalTokens = "total_tokens"
    }

    var relayBreakdown: RelayTokenUsageBreakdown {
        RelayTokenUsageBreakdown(
            inputTokens: inputTokens,
            cachedInputTokens: cachedInputTokens,
            outputTokens: outputTokens,
            reasoningOutputTokens: reasoningOutputTokens,
            totalTokens: totalTokens
        )
    }
}

private struct RateLimits: Decodable {
    let limitID: String?
    let limitName: String?
    let primary: Window?
    let secondary: Window?

    private enum CodingKeys: String, CodingKey {
        case limitID = "limit_id"
        case limitName = "limit_name"
        case primary
        case secondary
    }

    var relaySnapshot: RelayUsageSnapshot {
        RelayUsageSnapshot(
            limitID: limitID,
            limitName: limitName,
            primary: primary?.relayWindow,
            secondary: secondary?.relayWindow
        )
    }

    struct Window: Decodable {
        let usedPercent: Double
        let windowMinutes: Int64?
        let resetsAt: Int64?

        private enum CodingKeys: String, CodingKey {
            case usedPercent = "used_percent"
            case windowMinutes = "window_minutes"
            case resetsAt = "resets_at"
        }

        var relayWindow: RelayRateLimitWindow {
            RelayRateLimitWindow(
                usedPercent: Int(usedPercent.rounded()),
                windowDurationMins: windowMinutes,
                resetsAt: resetsAt
            )
        }
    }
}
