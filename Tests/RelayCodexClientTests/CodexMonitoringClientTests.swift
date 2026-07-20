import Foundation
import RelayCore
import Testing
@testable import RelayCodexClient

struct CodexMonitoringClientTests {
    @Test
    func enrichesDesktopOwnedTaskFromItsSharedRollout() async throws {
        let rollout = FileManager.default.temporaryDirectory
            .appending(path: UUID().uuidString)
            .appendingPathExtension("jsonl")
        try """
        {"type":"event_msg","payload":{"type":"task_started","turn_id":"turn-live"}}
        {"type":"event_msg","payload":{"type":"token_count","info":{"total_token_usage":{"input_tokens":80000,"cached_input_tokens":20000,"output_tokens":10000,"reasoning_output_tokens":5000,"total_tokens":95000},"last_token_usage":{"input_tokens":30000,"cached_input_tokens":5000,"output_tokens":5000,"reasoning_output_tokens":2000,"total_tokens":35000},"model_context_window":200000},"rate_limits":{"limit_id":"codex","primary":{"used_percent":42,"window_minutes":300,"resets_at":1784228400},"secondary":{"used_percent":68,"window_minutes":10080,"resets_at":1784814400}}}}
        """.write(to: rollout, atomically: true, encoding: .utf8)
        let rpc = DesktopOwnedTaskFixtureRPC(rolloutPath: rollout.path)
        let source = MonitoringEventSource()
        let client = CodexMonitoringClient(
            rpc: rpc,
            serverEvents: source.stream
        )

        let snapshot = try await client.snapshot(limit: 1)

        #expect(snapshot.tasks.first?.attentionState == .running)
        #expect(
            snapshot.tokenUsageByThreadID["desktop-worker"]?
                .contextPercentage == 17.5
        )
        #expect(snapshot.usage?.primary?.windowDurationMins == 300)
        #expect(snapshot.usage?.secondary?.windowDurationMins == 10_080)
    }

    @Test
    func readsTasksAndBothRateLimitWindowsAndResetCredits() async throws {
        let rpc = MonitoringFixtureRPC()
        let source = MonitoringEventSource()
        let client = CodexMonitoringClient(
            rpc: rpc,
            serverEvents: source.stream
        )

        let snapshot = try await client.snapshot(limit: 2)

        #expect(snapshot.tasks.count == 2)
        #expect(snapshot.tasks.first?.latestUpdate == "Checking fixtures.")
        #expect(snapshot.tasks.first?.attentionState == .needsInput)
        #expect(snapshot.usage?.primary?.windowDurationMins == 300)
        #expect(snapshot.usage?.primary?.usedPercent == 42)
        #expect(snapshot.usage?.primary?.resetsAt == 1_784_228_400)
        #expect(snapshot.usage?.secondary?.windowDurationMins == 10_080)
        #expect(snapshot.usage?.secondary?.usedPercent == 73)
        #expect(snapshot.usage?.secondary?.resetsAt == 1_784_814_400)
        #expect(snapshot.usage?.resetCreditsAvailableCount == 2)
        #expect(snapshot.usage?.resetCredits?.first?.title == "One-time reset")
        #expect(snapshot.usage?.resetCredits?.first?.expiresAt == 1_784_901_000)
        #expect(
            await rpc.recordedMethods()
                == [
                    "thread/list",
                    "thread/read",
                    "thread/read",
                    "account/rateLimits/read",
                ]
        )
    }

    @Test
    func consumingResetCreditUsesProtocolIdempotencyKey() async throws {
        let rpc = ResetCreditFixtureRPC()
        let source = MonitoringEventSource()
        let client = CodexMonitoringClient(
            rpc: rpc,
            serverEvents: source.stream
        )

        let outcome = try await client.consumeResetCredit(creditID: "reset-1")
        let params = await rpc.recordedParams()

        #expect(outcome == .redeemed)
        #expect(params?["creditId"]?.stringValue == "reset-1")
        #expect(params?["attemptId"] == nil)
        #expect(
            params?["idempotencyKey"]?.stringValue.flatMap(UUID.init(uuidString:))
                != nil
        )
    }

    @Test
    func preservesUnavailableUsageInsteadOfInventingZeroes() async throws {
        let rpc = MonitoringFixtureRPC(missingUsage: true)
        let source = MonitoringEventSource()
        let client = CodexMonitoringClient(
            rpc: rpc,
            serverEvents: source.stream
        )

        let snapshot = try await client.snapshot(limit: 1)

        #expect(snapshot.usage?.primary == nil)
        #expect(snapshot.usage?.secondary == nil)
        #expect(snapshot.usage?.resetCreditsAvailableCount == nil)
    }

    @Test
    func mergesSparseRateLimitUpdatesWithoutErasingKnownValues() async throws {
        let rpc = MonitoringFixtureRPC()
        let source = MonitoringEventSource()
        let client = CodexMonitoringClient(
            rpc: rpc,
            serverEvents: source.stream
        )
        _ = try await client.snapshot(limit: 1)
        var iterator = client.events().makeAsyncIterator()

        source.yield(
            .notification(
                method: "account/rateLimits/updated",
                params: .object([
                    "rateLimits": .object([
                        "primary": .object([
                            "usedPercent": .integer(55),
                        ]),
                    ]),
                ])
            )
        )

        let updated = await iterator.next()?.usage

        #expect(updated?.limitID == "codex")
        #expect(updated?.limitName == "Codex")
        #expect(updated?.primary?.usedPercent == 55)
        #expect(updated?.primary?.windowDurationMins == 300)
        #expect(updated?.primary?.resetsAt == 1_784_228_400)
        #expect(updated?.secondary?.usedPercent == 73)
        #expect(updated?.secondary?.windowDurationMins == 10_080)
        #expect(updated?.secondary?.resetsAt == 1_784_814_400)
        #expect(updated?.resetCreditsAvailableCount == 2)
        #expect(updated?.resetCredits?.first?.title == "One-time reset")
    }

    @Test
    func choosesNewestMeaningfulItemByActualItemOrder() async throws {
        let rpc = MonitoringFixtureRPC(newerCommandUpdate: true)
        let source = MonitoringEventSource()
        let client = CodexMonitoringClient(
            rpc: rpc,
            serverEvents: source.stream
        )

        let snapshot = try await client.snapshot(limit: 1)

        #expect(snapshot.tasks.first?.latestUpdate == "Running: swift test")
    }

    @Test
    func latestFailedTurnPrioritizesItsTerminalError() async throws {
        let record = try JSONDecoder().decode(
            CodexMonitoringThreadRecord.self,
            from: Data(
                """
                {
                  "id":"failed", "name":null, "preview":"Failed", "cwd":"/tmp",
                  "updatedAt":100, "status":{"type":"idle","activeFlags":[]},
                  "turns":[{"status":"failed","error":{"message":"Compilation failed"},
                    "items":[{"type":"agentMessage","text":"Earlier progress"}]}]
                }
                """.utf8
            )
        )

        #expect(record.latestTurnStatus == .failed)
        #expect(record.latestTurnError == "Compilation failed")
        #expect(record.latestUpdate == "Failed: Compilation failed")
        #expect(record.activity.attentionState == .failed)
    }

    @Test
    func retainsCompleteFinalAnswerForAttentionClassification() throws {
        let text = String(repeating: "x", count: 900)
            + " Please review and reply approved."
        let record = try JSONDecoder().decode(
            CodexMonitoringThreadRecord.self,
            from: Data(
                """
                {
                  "id":"completed", "name":null, "preview":"Done",
                  "cwd":"/tmp", "updatedAt":100,
                  "status":{"type":"idle","activeFlags":[]},
                  "turns":[{"id":"turn-final","status":"completed",
                    "items":[{"type":"agentMessage",
                      "phase":"final_answer","text":"\(text)"}]}]
                }
                """.utf8
            )
        )

        #expect(record.latestFinalResponse?.turnID == "turn-final")
        #expect(record.latestFinalResponse?.text == text)
        #expect(record.latestFinalResponse?.fingerprint.isEmpty == false)
        #expect(record.latestUpdate?.hasSuffix("…") == true)
    }

    @Test
    func decodesStatusTokenAndRateLimitNotifications() async throws {
        let rpc = MonitoringFixtureRPC()
        let source = MonitoringEventSource()
        let client = CodexMonitoringClient(
            rpc: rpc,
            serverEvents: source.stream
        )
        var iterator = client.events().makeAsyncIterator()

        source.yield(
            .notification(
                method: "thread/status/changed",
                params: .object([
                    "threadId": .string("worker-1"),
                    "status": .object([
                        "type": .string("active"),
                        "activeFlags": .array([
                            .string("waitingOnApproval"),
                        ]),
                    ]),
                ])
            )
        )
        source.yield(
            .notification(
                method: "thread/tokenUsage/updated",
                params: Self.tokenUsageNotification
            )
        )
        source.yield(
            .notification(
                method: "account/rateLimits/updated",
                params: .object([
                    "rateLimits": Self.rateLimits,
                ])
            )
        )

        let status = await iterator.next()
        let tokens = await iterator.next()
        let limits = await iterator.next()

        #expect(
            status
                == .threadStatusChanged(
                    threadID: "worker-1",
                    status: .active,
                    activeFlags: [.waitingOnApproval]
                )
        )
        #expect(
            tokens
                == .threadTokenUsageUpdated(
                    threadID: "worker-1",
                    turnID: "turn-1",
                    usage: RelayThreadTokenUsage(
                        total: .init(
                            inputTokens: 80_000,
                            cachedInputTokens: 20_000,
                            outputTokens: 10_000,
                            reasoningOutputTokens: 5_000,
                            totalTokens: 95_000
                        ),
                        last: .init(
                            inputTokens: 30_000,
                            cachedInputTokens: 5_000,
                            outputTokens: 5_000,
                            reasoningOutputTokens: 2_000,
                            totalTokens: 35_000
                        ),
                        modelContextWindow: 200_000
                    )
                )
        )
        #expect(limits?.usage?.primary?.usedPercent == 42)

        let snapshot = try await client.snapshot(limit: 1)
        #expect(
            snapshot.tokenUsageByThreadID["worker-1"]?
                .contextPercentage == 17.5
        )
    }

    private static let tokenUsageNotification: JSONValue = .object([
        "threadId": .string("worker-1"),
        "turnId": .string("turn-1"),
        "tokenUsage": .object([
            "total": tokenBreakdown(
                input: 80_000,
                cached: 20_000,
                output: 10_000,
                reasoning: 5_000,
                total: 95_000
            ),
            "last": tokenBreakdown(
                input: 30_000,
                cached: 5_000,
                output: 5_000,
                reasoning: 2_000,
                total: 35_000
            ),
            "modelContextWindow": .integer(200_000),
        ]),
    ])

    fileprivate static let rateLimits: JSONValue = .object([
        "limitId": .string("codex"),
        "limitName": .string("Codex"),
        "primary": .object([
            "usedPercent": .integer(42),
            "windowDurationMins": .integer(300),
            "resetsAt": .integer(1_784_228_400),
        ]),
        "secondary": .object([
            "usedPercent": .integer(73),
            "windowDurationMins": .integer(10_080),
            "resetsAt": .integer(1_784_814_400),
        ]),
    ])

    private static func tokenBreakdown(
        input: Int64,
        cached: Int64,
        output: Int64,
        reasoning: Int64,
        total: Int64
    ) -> JSONValue {
        .object([
            "inputTokens": .integer(input),
            "cachedInputTokens": .integer(cached),
            "outputTokens": .integer(output),
            "reasoningOutputTokens": .integer(reasoning),
            "totalTokens": .integer(total),
        ])
    }
}

private actor DesktopOwnedTaskFixtureRPC: CodexRPCRequesting {
    let rolloutPath: String

    init(rolloutPath: String) {
        self.rolloutPath = rolloutPath
    }

    func requestJSON(
        method: String,
        params: JSONValue,
        timeout: Duration
    ) async throws -> JSONValue {
        switch method {
        case "thread/list", "thread/read":
            let thread: JSONValue = .object([
                "id": .string("desktop-worker"),
                "name": .string("Desktop worker"),
                "preview": .string("Desktop worker"),
                "cwd": .string("/tmp"),
                "updatedAt": .integer(1_784_210_400),
                "path": .string(rolloutPath),
                "status": .object(["type": .string("notLoaded")]),
                "turns": .array([
                    .object([
                        "status": .string("interrupted"),
                        "items": .array([]),
                    ]),
                ]),
            ])
            return method == "thread/list"
                ? .object(["data": .array([thread])])
                : .object(["thread": thread])
        case "account/rateLimits/read":
            return .object([
                "rateLimits": .object([
                    "limitId": .string("codex"),
                    "primary": .object([
                        "usedPercent": .integer(70),
                        "windowDurationMins": .integer(10_080),
                    ]),
                ]),
                "rateLimitResetCredits": .null,
            ])
        default:
            throw MonitoringFixtureError.unexpectedMethod(method)
        }
    }
}

private actor MonitoringFixtureRPC: CodexRPCRequesting {
    private let missingUsage: Bool
    private let newerCommandUpdate: Bool
    private var methods: [String] = []

    init(
        missingUsage: Bool = false,
        newerCommandUpdate: Bool = false
    ) {
        self.missingUsage = missingUsage
        self.newerCommandUpdate = newerCommandUpdate
    }

    func requestJSON(
        method: String,
        params: JSONValue,
        timeout: Duration
    ) async throws -> JSONValue {
        methods.append(method)
        switch method {
        case "thread/list":
            return .object([
                "data": .array([
                    Self.thread(id: "worker-1", waiting: true),
                    Self.thread(id: "worker-2", waiting: false),
                ]),
            ])
        case "thread/read":
            let id = params["threadId"]?.stringValue ?? "worker-1"
            return .object([
                "thread": Self.thread(
                    id: id,
                    waiting: id == "worker-1",
                    includeTurns: true,
                    newerCommandUpdate: newerCommandUpdate
                ),
            ])
        case "account/rateLimits/read":
            if missingUsage {
                return .object([
                    "rateLimits": .object([
                        "primary": .null,
                        "secondary": .null,
                    ]),
                    "rateLimitResetCredits": .null,
                ])
            }
            return .object([
                "rateLimits": CodexMonitoringClientTests.rateLimits,
                "rateLimitResetCredits": .object([
                    "availableCount": .integer(2),
                    "credits": .array([
                        .object([
                            "id": .string("reset-1"),
                            "title": .string("One-time reset"),
                            "description": .string("Restore Codex capacity"),
                            "grantedAt": .integer(1_784_200_000),
                            "expiresAt": .integer(1_784_901_000),
                            "resetType": .string("codexRateLimits"),
                            "status": .string("available"),
                        ]),
                    ]),
                ]),
            ])
        default:
            throw MonitoringFixtureError.unexpectedMethod(method)
        }
    }

    func recordedMethods() -> [String] {
        methods
    }

    private static func thread(
        id: String,
        waiting: Bool,
        includeTurns: Bool = false,
        newerCommandUpdate: Bool = false
    ) -> JSONValue {
        .object([
            "id": .string(id),
            "name": .string("Monitor \(id)"),
            "preview": .string("Monitor \(id)"),
            "cwd": .string("/Users/ayushrungta/Work/Relay"),
            "updatedAt": .integer(1_784_210_400),
            "status": .object([
                "type": .string(waiting ? "active" : "idle"),
                "activeFlags": waiting
                    ? .array([.string("waitingOnUserInput")])
                    : .array([]),
            ]),
            "turns": includeTurns
                ? .array([
                    .object([
                        "id": .string("turn-1"),
                        "status": .string("inProgress"),
                        "items": .array(
                            [
                                .object([
                                    "id": .string("message-1"),
                                    "type": .string("agentMessage"),
                                    "phase": .string("commentary"),
                                    "text": .string("Checking fixtures."),
                                ]),
                            ] + (
                                newerCommandUpdate
                                    ? [
                                        .object([
                                            "id": .string("command-1"),
                                            "type": .string(
                                                "commandExecution"
                                            ),
                                            "command": .string("swift test"),
                                            "status": .string("inProgress"),
                                        ]),
                                    ]
                                    : []
                            )
                        ),
                    ]),
                ])
                : .array([]),
        ])
    }
}

private final class MonitoringEventSource: @unchecked Sendable {
    let stream: AsyncStream<CodexServerEvent>
    private let continuation: AsyncStream<CodexServerEvent>.Continuation

    init() {
        let pair = AsyncStream<CodexServerEvent>.makeStream()
        stream = pair.stream
        continuation = pair.continuation
    }

    func yield(_ event: CodexServerEvent) {
        continuation.yield(event)
    }
}

private enum MonitoringFixtureError: Error {
    case unexpectedMethod(String)
}

private actor ResetCreditFixtureRPC: CodexRPCRequesting {
    private var params: JSONValue?

    func requestJSON(
        method: String,
        params: JSONValue,
        timeout: Duration
    ) async throws -> JSONValue {
        guard method == "account/rateLimitResetCredit/consume" else {
            throw MonitoringFixtureError.unexpectedMethod(method)
        }
        self.params = params
        return .object(["outcome": .string("redeemed")])
    }

    func recordedParams() -> JSONValue? {
        params
    }
}
