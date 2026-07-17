import Foundation
import RelayCore
import Testing
@testable import RelayCodexClient

struct CodexTaskOperationsClientTests {
    @Test
    func startsAVisibleWorkerThreadAndItsFirstTurn() async throws {
        let rpc = TaskOperationsFixtureRPC()
        let service = CodexTaskOperationsClient(rpc: rpc)

        let launch = try await service.startTask(
            prompt: "Audit the Relay transport",
            cwd: "/Users/ayushrungta/Work/Relay"
        )

        #expect(launch.thread.id == "worker-1")
        #expect(launch.turnID == "turn-1")
        #expect(await rpc.recordedMethods() == ["thread/start", "turn/start"])
        #expect(
            await rpc.parameter(
                method: "turn/start",
                key: "threadId"
            )?.stringValue == "worker-1"
        )
        #expect(
            await rpc.firstInputText(method: "turn/start")
                == "Audit the Relay transport"
        )
        #expect(
            await rpc.parameter(
                method: "thread/start",
                key: "approvalPolicy"
            ) == .string("never")
        )
        #expect(
            await rpc.parameter(
                method: "thread/start",
                key: "sandbox"
            ) == .string("workspace-write")
        )
    }

    @Test
    func steersAndInterruptsTheActiveTurn() async throws {
        let rpc = TaskOperationsFixtureRPC()
        let service = CodexTaskOperationsClient(rpc: rpc)

        let launch = try await service.sendToTask(
            id: "active-worker",
            prompt: "Also check cancellation"
        )
        try await service.interruptTask(id: "active-worker")

        #expect(launch.turnID == "turn-active")
        #expect(
            await rpc.recordedMethods()
                == [
                    "thread/resume",
                    "turn/steer",
                    "thread/resume",
                    "turn/interrupt",
                ]
        )
        #expect(
            await rpc.parameter(
                method: "turn/steer",
                key: "expectedTurnId"
            )?.stringValue == "turn-active"
        )
        #expect(
            await rpc.parameter(
                method: "turn/interrupt",
                key: "turnId"
            )?.stringValue == "turn-active"
        )
        #expect(
            await rpc.parameter(
                method: "thread/resume",
                key: "approvalPolicy"
            ) == .string("never")
        )
    }

    @Test
    func resumesAnIdleStoredTaskBeforeStartingItsNextTurn() async throws {
        let rpc = TaskOperationsFixtureRPC()
        let service = CodexTaskOperationsClient(rpc: rpc)

        let launch = try await service.sendToTask(
            id: "idle-worker",
            prompt: "Continue with the UI"
        )

        #expect(launch.thread.id == "idle-worker")
        #expect(launch.turnID == "turn-1")
        #expect(
            await rpc.recordedMethods()
                == ["thread/resume", "turn/start"]
        )
    }

    @Test
    func listsTasksUsingTheirCodexNames() async throws {
        let rpc = TaskOperationsFixtureRPC()
        let service = CodexTaskOperationsClient(rpc: rpc)

        let tasks = try await service.listTasks(limit: 10)

        #expect(tasks.first?.name == "Review recent agent changes")
        #expect(tasks.first?.preview == "codex://threads/worker-1")
    }

    @Test
    func readsTheLatestWorkerProgressMessage() async throws {
        let rpc = TaskOperationsFixtureRPC()
        let service = CodexTaskOperationsClient(rpc: rpc)

        let runtime = try await service.getTask(id: "active-worker")

        #expect(
            runtime.latestUpdate
                == "I found the race and am verifying the fix."
        )
    }

    @Test
    func unknownTurnStatusDoesNotBreakReadSendOrInterrupt() async throws {
        let rpc = TaskOperationsFixtureRPC(includesUnknownTurnStatus: true)
        let service = CodexTaskOperationsClient(rpc: rpc)

        let runtime = try await service.getTask(id: "active-worker")
        let launch = try await service.sendToTask(
            id: "active-worker",
            prompt: "Continue"
        )
        try await service.interruptTask(id: "active-worker")

        #expect(runtime.activeTurnID == "turn-active")
        #expect(launch.turnID == "turn-active")
        #expect(
            await rpc.recordedMethods()
                == [
                    "thread/read",
                    "thread/resume",
                    "turn/steer",
                    "thread/resume",
                    "turn/interrupt",
                ]
        )
    }
}

private actor TaskOperationsFixtureRPC: CodexRPCRequesting {
    private var requests: [(method: String, params: JSONValue)] = []
    private let includesUnknownTurnStatus: Bool

    init(includesUnknownTurnStatus: Bool = false) {
        self.includesUnknownTurnStatus = includesUnknownTurnStatus
    }

    func requestJSON(
        method: String,
        params: JSONValue,
        timeout: Duration
    ) async throws -> JSONValue {
        requests.append((method, params))

        switch method {
        case "thread/list":
            return .object([
                "data": .array([Self.thread(
                    id: "worker-1",
                    active: false,
                    includesUnknownTurnStatus: includesUnknownTurnStatus
                )]),
            ])
        case "thread/start":
            return .object([
                "thread": Self.thread(
                    id: "worker-1",
                    active: false,
                    includesUnknownTurnStatus: includesUnknownTurnStatus
                ),
            ])
        case "turn/start":
            return .object([
                "turn": .object([
                    "id": .string("turn-1"),
                    "status": .string("inProgress"),
                ]),
            ])
        case "thread/read":
            return .object([
                "thread": Self.thread(
                    id: "active-worker",
                    active: true,
                    includesUnknownTurnStatus: includesUnknownTurnStatus
                ),
            ])
        case "thread/resume":
            let id = params["threadId"]?.stringValue ?? "active-worker"
            return .object([
                "thread": Self.thread(
                    id: id,
                    active: id == "active-worker",
                    includesUnknownTurnStatus: includesUnknownTurnStatus
                ),
            ])
        case "turn/steer":
            return .object(["turnId": .string("turn-active")])
        case "turn/interrupt":
            return .object([:])
        default:
            throw FixtureError.unexpectedMethod(method)
        }
    }

    func recordedMethods() -> [String] {
        requests.map(\.method)
    }

    func parameter(method: String, key: String) -> JSONValue? {
        requests.first { $0.method == method }?.params[key]
    }

    func firstInputText(method: String) -> String? {
        requests
            .first { $0.method == method }?
            .params["input"]?
            .arrayValue?
            .first?["text"]?
            .stringValue
    }

    private static func thread(
        id: String,
        active: Bool,
        includesUnknownTurnStatus: Bool
    ) -> JSONValue {
        var turns: [JSONValue] = []
        if includesUnknownTurnStatus {
            turns.append(.object([
                "id": .string("turn-future"),
                "status": .string("pausedForReview"),
            ]))
        }
        if active {
            turns.append(.object([
                "id": .string("turn-active"),
                "status": .string("inProgress"),
                "items": .array([
                    .object([
                        "id": .string("message-1"),
                        "type": .string("agentMessage"),
                        "phase": .string("commentary"),
                        "text": .string(
                            "I found the race and am verifying the fix."
                        ),
                    ]),
                ]),
            ]))
        }
        return .object([
            "id": .string(id),
            "name": .string("Review recent agent changes"),
            "preview": .string("codex://threads/worker-1"),
            "cwd": .string("/Users/ayushrungta/Work/Relay"),
            "updatedAt": .integer(1_784_210_400),
            "status": .object([
                "type": .string(active ? "active" : "idle"),
            ]),
            "turns": .array(turns),
        ])
    }
}

private enum FixtureError: Error {
    case unexpectedMethod(String)
}
