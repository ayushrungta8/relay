import Foundation
import RelayCore
import Testing
@testable import RelayCodexClient

struct CodexSessionLogSnapshotTests {
    @Test
    func readsRunningStateAndLatestContextFromDesktopRollout() throws {
        let url = try fixture(
            lines: [
                event("task_started", extra: "\"turn_id\":\"turn-1\""),
                tokenCount(lastTotal: 51_000, contextWindow: 258_400),
            ]
        )

        let snapshot = try CodexSessionLogSnapshot.read(from: url)

        #expect(snapshot.isRunning)
        #expect(snapshot.tokenUsage?.last.totalTokens == 51_000)
        #expect(snapshot.tokenUsage?.modelContextWindow == 258_400)
    }

    @Test
    func terminalEventEndsRunningStateWithoutDiscardingContext() throws {
        let url = try fixture(
            lines: [
                event("task_started", extra: "\"turn_id\":\"turn-1\""),
                tokenCount(lastTotal: 34_000, contextWindow: 200_000),
                event("task_complete", extra: "\"turn_id\":\"turn-1\""),
            ]
        )

        let snapshot = try CodexSessionLogSnapshot.read(from: url)

        #expect(!snapshot.isRunning)
        #expect(snapshot.tokenUsage?.contextPercentage == 17)
    }

    @Test
    func detectsUnresolvedDesktopApprovalFromRollout() throws {
        let callID = "call-approval"
        let url = try fixture(
            lines: [
                event("task_started", extra: "\"turn_id\":\"turn-1\""),
                try toolCall(
                    type: "custom_tool_call",
                    callID: callID,
                    name: "exec",
                    input: #"{"sandbox_permissions":"require_escalated"}"#
                ),
            ]
        )

        let snapshot = try CodexSessionLogSnapshot.read(from: url)

        #expect(snapshot.activeFlags == [.waitingOnApproval])
    }

    @Test
    func completedDesktopApprovalIsNoLongerPending() throws {
        let callID = "call-approval"
        let url = try fixture(
            lines: [
                event("task_started", extra: "\"turn_id\":\"turn-1\""),
                try toolCall(
                    type: "custom_tool_call",
                    callID: callID,
                    name: "exec",
                    input: #"{"sandbox_permissions":"require_escalated"}"#
                ),
                toolCallOutput(type: "custom_tool_call_output", callID: callID),
            ]
        )

        let snapshot = try CodexSessionLogSnapshot.read(from: url)

        #expect(snapshot.activeFlags.isEmpty)
    }

    @Test
    func detectsUnresolvedDesktopUserInputFromRollout() throws {
        let url = try fixture(
            lines: [
                event("task_started", extra: "\"turn_id\":\"turn-1\""),
                try toolCall(
                    type: "function_call",
                    callID: "call-input",
                    name: "request_user_input",
                    input: "{}"
                ),
            ]
        )

        let snapshot = try CodexSessionLogSnapshot.read(from: url)

        #expect(snapshot.activeFlags == [.waitingOnUserInput])
    }

    @Test
    func readsRateLimitWindowsUsingRolloutFieldNames() throws {
        let url = try fixture(
            lines: [tokenCount(
                lastTotal: 1_000,
                contextWindow: 10_000,
                rateLimits: """
                {"limit_id":"codex","limit_name":"Codex","primary":{"used_percent":42,"window_minutes":300,"resets_at":1784228400},"secondary":{"used_percent":68,"window_minutes":10080,"resets_at":1784814400}}
                """
            )]
        )

        let snapshot = try CodexSessionLogSnapshot.read(from: url)

        #expect(snapshot.usage?.primary?.windowDurationMins == 300)
        #expect(snapshot.usage?.primary?.usedPercent == 42)
        #expect(snapshot.usage?.secondary?.windowDurationMins == 10_080)
    }

    private func fixture(lines: [String]) throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appending(path: UUID().uuidString)
            .appendingPathExtension("jsonl")
        try (lines.joined(separator: "\n") + "\n")
            .write(to: url, atomically: true, encoding: .utf8)
        return url
    }

    private func event(_ type: String, extra: String) -> String {
        """
        {"timestamp":"2026-07-17T10:00:00Z","type":"event_msg","payload":{"type":"\(type)",\(extra)}}
        """
    }

    private func tokenCount(
        lastTotal: Int64,
        contextWindow: Int64,
        rateLimits: String = "null"
    ) -> String {
        """
        {"timestamp":"2026-07-17T10:00:01Z","type":"event_msg","payload":{"type":"token_count","info":{"total_token_usage":{"input_tokens":80000,"cached_input_tokens":20000,"cache_write_input_tokens":0,"output_tokens":10000,"reasoning_output_tokens":5000,"total_tokens":95000},"last_token_usage":{"input_tokens":30000,"cached_input_tokens":5000,"cache_write_input_tokens":0,"output_tokens":5000,"reasoning_output_tokens":2000,"total_tokens":\(lastTotal)},"model_context_window":\(contextWindow)},"rate_limits":\(rateLimits)}}
        """
    }

    private func toolCall(
        type: String,
        callID: String,
        name: String,
        input: String
    ) throws -> String {
        let data = try JSONEncoder().encode(input)
        let encodedInput = String(decoding: data, as: UTF8.self)
        return """
        {"timestamp":"2026-07-17T10:00:01Z","type":"response_item","payload":{"type":"\(type)","call_id":"\(callID)","name":"\(name)","input":\(encodedInput)}}
        """
    }

    private func toolCallOutput(type: String, callID: String) -> String {
        """
        {"timestamp":"2026-07-17T10:00:02Z","type":"response_item","payload":{"type":"\(type)","call_id":"\(callID)","output":[]}}
        """
    }
}
