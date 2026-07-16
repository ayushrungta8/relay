import Foundation
import RelayCore

public struct CodexTaskLaunch: Sendable, Equatable {
    public let thread: CodexThread
    public let turnID: String

    public init(thread: CodexThread, turnID: String) {
        self.thread = thread
        self.turnID = turnID
    }
}

public struct CodexTaskRuntime: Sendable, Equatable {
    public let thread: CodexThread
    public let activeTurnID: String?
    public let latestUpdate: String?

    public init(
        thread: CodexThread,
        activeTurnID: String?,
        latestUpdate: String? = nil
    ) {
        self.thread = thread
        self.activeTurnID = activeTurnID
        self.latestUpdate = latestUpdate
    }
}

public enum CodexTaskOperationsError: Error, Sendable {
    case emptyPrompt
    case noActiveTurn(String)
}

extension CodexTaskOperationsError: LocalizedError {
    public var errorDescription: String? {
        switch self {
        case .emptyPrompt:
            "Relay cannot start an empty Codex task."
        case let .noActiveTurn(threadID):
            "Codex task \(threadID) has no active turn to interrupt."
        }
    }
}

public protocol CodexTaskOperating: Sendable {
    func sendToTask(
        id: String,
        prompt: String
    ) async throws -> CodexTaskLaunch
    func interruptTask(id: String) async throws
}

public actor CodexTaskOperationsClient: CodexTaskOperating {
    private let rpc: any CodexRPCRequesting

    public init(rpc: any CodexRPCRequesting) {
        self.rpc = rpc
    }

    public func listTasks(limit: Int = 25) async throws -> [CodexThread] {
        let result = try await request(
            method: "thread/list",
            params: .object([
                "archived": .bool(false),
                "limit": .integer(Int64(limit)),
                "sortKey": .string("updated_at"),
            ]),
            as: ThreadListResult.self
        )
        return result.data.map(\.thread)
    }

    public func getTask(id: String) async throws -> CodexTaskRuntime {
        let result = try await request(
            method: "thread/read",
            params: .object([
                "threadId": .string(id),
                "includeTurns": .bool(true),
            ]),
            as: ThreadReadResult.self
        )
        return result.thread.runtime
    }

    public func startTask(
        prompt: String,
        cwd: String?
    ) async throws -> CodexTaskLaunch {
        let prompt = try normalizedPrompt(prompt)
        var startParameters: [String: JSONValue] = [
            "approvalPolicy": .string("never"),
            "ephemeral": .bool(false),
            "sandbox": .string("workspace-write"),
        ]
        if let cwd, !cwd.isEmpty {
            startParameters["cwd"] = .string(cwd)
        }

        let started = try await request(
            method: "thread/start",
            params: .object(startParameters),
            as: ThreadStartResult.self
        )
        return try await startTurn(
            thread: started.thread,
            prompt: prompt
        )
    }

    public func sendToTask(
        id: String,
        prompt: String
    ) async throws -> CodexTaskLaunch {
        let prompt = try normalizedPrompt(prompt)
        let runtime = try await resumeTask(id: id)

        if let activeTurnID = runtime.activeTurnID {
            let result = try await request(
                method: "turn/steer",
                params: .object([
                    "threadId": .string(id),
                    "expectedTurnId": .string(activeTurnID),
                    "input": Self.textInput(prompt),
                ]),
                as: TurnSteerResult.self
            )
            return CodexTaskLaunch(
                thread: runtime.thread,
                turnID: result.turnID
            )
        }

        return try await startTurn(
            thread: ThreadRecord(runtime.thread),
            prompt: prompt
        )
    }

    public func interruptTask(id: String) async throws {
        let runtime = try await resumeTask(id: id)
        guard let activeTurnID = runtime.activeTurnID else {
            throw CodexTaskOperationsError.noActiveTurn(id)
        }

        let _: EmptyResult = try await request(
            method: "turn/interrupt",
            params: .object([
                "threadId": .string(id),
                "turnId": .string(activeTurnID),
            ]),
            as: EmptyResult.self
        )
    }

    private func startTurn(
        thread: ThreadRecord,
        prompt: String
    ) async throws -> CodexTaskLaunch {
        let result = try await request(
            method: "turn/start",
            params: .object([
                "threadId": .string(thread.id),
                "input": Self.textInput(prompt),
            ]),
            as: TurnStartResult.self
        )
        return CodexTaskLaunch(
            thread: thread.thread,
            turnID: result.turn.id
        )
    }

    private func resumeTask(id: String) async throws -> CodexTaskRuntime {
        let result = try await request(
            method: "thread/resume",
            params: .object([
                "approvalPolicy": .string("never"),
                "threadId": .string(id),
                "excludeTurns": .bool(false),
            ]),
            timeout: .seconds(20),
            as: ThreadReadResult.self
        )
        return result.thread.runtime
    }

    private func normalizedPrompt(_ prompt: String) throws -> String {
        let normalized = prompt.trimmingCharacters(
            in: .whitespacesAndNewlines
        )
        guard !normalized.isEmpty else {
            throw CodexTaskOperationsError.emptyPrompt
        }
        return normalized
    }

    private func request<Result: Decodable>(
        method: String,
        params: JSONValue,
        timeout: Duration = .seconds(8),
        as type: Result.Type
    ) async throws -> Result {
        let value = try await rpc.requestJSON(
            method: method,
            params: params,
            timeout: timeout
        )
        let data = try JSONEncoder().encode(value)
        return try JSONDecoder().decode(type, from: data)
    }

    private static func textInput(_ text: String) -> JSONValue {
        .array([
            .object([
                "type": .string("text"),
                "text": .string(text),
            ]),
        ])
    }
}

private struct ThreadListResult: Decodable {
    let data: [ThreadRecord]
}

private struct ThreadStartResult: Decodable {
    let thread: ThreadRecord
}

private struct ThreadReadResult: Decodable {
    let thread: ThreadRecord
}

private struct TurnStartResult: Decodable {
    let turn: TurnRecord
}

private struct TurnSteerResult: Decodable {
    let turnID: String

    private enum CodingKeys: String, CodingKey {
        case turnID = "turnId"
    }
}

private struct EmptyResult: Decodable {}

private struct ThreadRecord: Decodable {
    let id: String
    let name: String?
    let preview: String
    let cwd: String
    let updatedAt: Int
    let status: StatusRecord
    let turns: [TurnRecord]

    init(_ thread: CodexThread) {
        id = thread.id
        name = thread.name
        preview = thread.preview
        cwd = thread.cwd
        updatedAt = thread.updatedAt
        status = StatusRecord(type: thread.status.rawValue)
        turns = []
    }

    var thread: CodexThread {
        CodexThread(
            id: id,
            name: name,
            preview: preview,
            cwd: cwd,
            updatedAt: updatedAt,
            status: status.threadStatus,
            activeFlags: status.activeFlags ?? []
        )
    }

    var runtime: CodexTaskRuntime {
        CodexTaskRuntime(
            thread: thread,
            activeTurnID: turns.last {
                $0.status == .inProgress
            }?.id,
            latestUpdate: latestUpdate
        )
    }

    private var latestUpdate: String? {
        for turn in turns.reversed() {
            if let message = turn.items?
                .reversed()
                .first(where: {
                    $0.type == "agentMessage"
                        && !($0.text ?? "").isEmpty
                })?
                .text {
                return Self.normalizedUpdate(message)
            }
            if let plan = turn.items?
                .reversed()
                .first(where: {
                    $0.type == "plan"
                        && !($0.text ?? "").isEmpty
                })?
                .text {
                return Self.normalizedUpdate(plan)
            }
            if let command = turn.items?
                .reversed()
                .first(where: {
                    $0.type == "commandExecution"
                        && !($0.command ?? "").isEmpty
                }) {
                let prefix = command.status == "inProgress"
                    ? "Running"
                    : "Last command"
                return Self.normalizedUpdate(
                    "\(prefix): \(command.command ?? "")"
                )
            }
            if let message = turn.error?.message, !message.isEmpty {
                return Self.normalizedUpdate("Failed: \(message)")
            }
        }
        return nil
    }

    private static func normalizedUpdate(_ text: String) -> String {
        let normalized = text.trimmingCharacters(
            in: .whitespacesAndNewlines
        )
        let limit = 800
        guard normalized.count > limit else { return normalized }
        return String(normalized.prefix(limit)) + "…"
    }
}

private struct StatusRecord: Decodable {
    let type: String
    let activeFlags: [CodexThreadActiveFlag]?

    init(
        type: String,
        activeFlags: [CodexThreadActiveFlag]? = nil
    ) {
        self.type = type
        self.activeFlags = activeFlags
    }

    var threadStatus: CodexThreadStatus {
        CodexThreadStatus(rawValue: type) ?? .unknown
    }
}

private struct TurnRecord: Decodable {
    let id: String
    let status: TurnStatus
    let items: [ThreadItemRecord]?
    let error: TurnErrorRecord?
}

private struct ThreadItemRecord: Decodable {
    let type: String
    let text: String?
    let command: String?
    let status: String?
}

private struct TurnErrorRecord: Decodable {
    let message: String
}

private enum TurnStatus: String, Decodable {
    case completed
    case interrupted
    case failed
    case inProgress
}
