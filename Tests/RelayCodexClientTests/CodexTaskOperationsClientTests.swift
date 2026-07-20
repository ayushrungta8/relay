import Foundation
import RelayCore
import Testing
@testable import RelayCodexClient

struct CodexTaskOperationsClientTests {
    @Test
    func runningDesktopTaskUsesDesktopDeliveryInsteadOfResumingIt() async throws {
        let rollout = FileManager.default.temporaryDirectory
            .appending(path: UUID().uuidString)
            .appendingPathExtension("jsonl")
        try """
        {"type":"event_msg","payload":{"type":"task_started","turn_id":"live-turn"}}
        """.write(to: rollout, atomically: true, encoding: .utf8)
        let rpc = DesktopTaskOperationsRPC(rolloutPath: rollout.path)
        let delivery = DesktopDeliveryRecorder()
        let service = CodexTaskOperationsClient(
            rpc: rpc,
            sendToDesktopTask: { id, prompt in
                await delivery.record(id: id, prompt: prompt)
            }
        )

        let launch = try await service.sendToTask(
            id: "desktop-worker",
            prompt: "Please continue"
        )

        #expect(launch.turnID == "live-turn")
        let delivered = await delivery.value()
        #expect(delivered?.0 == "desktop-worker")
        #expect(delivered?.1 == "Please continue")
        #expect(await rpc.recordedMethods() == ["thread/read"])
    }

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
                key: "cwd"
            ) == .string("/Users/ayushrungta/Work/Relay")
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
    func startsProjectlessWorkInANormalCodexChatDirectory() async throws {
        let rpc = TaskOperationsFixtureRPC()
        let service = CodexTaskOperationsClient(
            rpc: rpc,
            createProjectlessDirectory: { prompt in
                #expect(prompt == "Change the system theme")
                return "/Users/test/Documents/Codex/2026-07-20/change-theme"
            }
        )

        _ = try await service.startTask(
            prompt: "Change the system theme",
            cwd: nil
        )

        #expect(
            await rpc.parameter(
                method: "thread/start",
                key: "cwd"
            ) == .string(
                "/Users/test/Documents/Codex/2026-07-20/change-theme"
            )
        )
    }

    @Test
    func projectlessDirectoryIsDatedReadableAndUnique() throws {
        let root = FileManager.default.temporaryDirectory
            .appending(path: UUID().uuidString, directoryHint: .isDirectory)
        defer { try? FileManager.default.removeItem(at: root) }
        let now = Date(timeIntervalSince1970: 1_784_563_200)

        let first = try CodexTaskOperationsClient.makeProjectlessDirectory(
            for: "Change my system theme to dark mode",
            root: root,
            now: now
        )
        let second = try CodexTaskOperationsClient.makeProjectlessDirectory(
            for: "Change my system theme to dark mode",
            root: root,
            now: now
        )

        #expect(first.contains("change-my-system-theme-to-dark-mode"))
        #expect(second.hasSuffix("-2"))
        var isDirectory: ObjCBool = false
        #expect(
            FileManager.default.fileExists(
                atPath: first,
                isDirectory: &isDirectory
            ) && isDirectory.boolValue
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

private actor DesktopDeliveryRecorder {
    private var delivered: (String, String)?

    func record(id: String, prompt: String) {
        delivered = (id, prompt)
    }

    func value() -> (String, String)? { delivered }
}

private actor DesktopTaskOperationsRPC: CodexRPCRequesting {
    let rolloutPath: String
    private var methods: [String] = []

    init(rolloutPath: String) {
        self.rolloutPath = rolloutPath
    }

    func requestJSON(
        method: String,
        params: JSONValue,
        timeout: Duration
    ) async throws -> JSONValue {
        methods.append(method)
        guard method == "thread/read" else {
            throw FixtureError.unexpectedMethod(method)
        }
        return .object([
            "thread": .object([
                "id": .string("desktop-worker"),
                "name": .string("Desktop worker"),
                "preview": .string("Desktop worker"),
                "cwd": .string("/tmp"),
                "updatedAt": .integer(1_784_210_400),
                "path": .string(rolloutPath),
                "status": .object(["type": .string("notLoaded")]),
                "turns": .array([
                    .object([
                        "id": .string("live-turn"),
                        "status": .string("interrupted"),
                        "items": .array([]),
                    ]),
                ]),
            ]),
        ])
    }

    func recordedMethods() -> [String] { methods }
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
