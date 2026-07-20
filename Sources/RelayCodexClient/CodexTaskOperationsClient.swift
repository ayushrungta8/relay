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
    case desktopDeliveryUnavailable(String)
}

extension CodexTaskOperationsError: LocalizedError {
    public var errorDescription: String? {
        switch self {
        case .emptyPrompt:
            "Relay cannot start an empty Codex task."
        case let .noActiveTurn(threadID):
            "Codex task \(threadID) has no active turn to interrupt."
        case let .desktopDeliveryUnavailable(threadID):
            "Codex task \(threadID) is running in Codex Desktop, but desktop follow-up delivery is unavailable."
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
    public typealias SendToDesktopTask = @Sendable (
        _ id: String,
        _ prompt: String
    ) async throws -> Void

    private let rpc: any CodexRPCRequesting
    private let sendToDesktopTask: SendToDesktopTask?
    private let createProjectlessDirectory:
        @Sendable (_ prompt: String) throws -> String

    public init(
        rpc: any CodexRPCRequesting,
        sendToDesktopTask: SendToDesktopTask? = nil,
        createProjectlessDirectory:
            (@Sendable (_ prompt: String) throws -> String)? = nil
    ) {
        self.rpc = rpc
        self.sendToDesktopTask = sendToDesktopTask
        self.createProjectlessDirectory = createProjectlessDirectory ?? {
            try Self.makeProjectlessDirectory(for: $0)
        }
    }

    public func listTasks(limit: Int = 25) async throws -> [CodexThread] {
        guard limit > 0 else { return [] }
        var threads: [CodexThread] = []
        var cursor: String?
        repeat {
            let pageLimit = min(100, limit - threads.count)
            var params: [String: JSONValue] = [
                "archived": .bool(false),
                "limit": .integer(Int64(pageLimit)),
                "sortKey": .string("updated_at"),
            ]
            if let cursor {
                params["cursor"] = .string(cursor)
            }
            let result = try await request(
                method: "thread/list",
                params: .object(params),
                as: ThreadListResult.self
            )
            threads.append(contentsOf: result.data.map(\.thread))
            let nextCursor = result.nextCursor
            guard !result.data.isEmpty, nextCursor != cursor else { break }
            cursor = nextCursor
        } while cursor != nil && threads.count < limit
        return Array(threads.prefix(limit))
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
        let cwd = try cwd ?? createProjectlessDirectory(prompt)
        let startParameters: [String: JSONValue] = [
            "approvalPolicy": .string("never"),
            "cwd": .string(cwd),
            "ephemeral": .bool(false),
            "sandbox": .string("workspace-write"),
        ]

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
        if let sendToDesktopTask {
            let inspected = try await readTask(id: id)
            if inspected.status.threadStatus == .notLoaded,
               let path = inspected.path,
               let session = try? CodexSessionLogSnapshot.read(
                   from: URL(filePath: path)
               ), session.isRunning,
               let turnID = session.activeTurnID {
                try await sendToDesktopTask(id, prompt)
                return CodexTaskLaunch(
                    thread: inspected.thread,
                    turnID: turnID
                )
            }
        }
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

    private func readTask(id: String) async throws -> ThreadRecord {
        let result = try await request(
            method: "thread/read",
            params: .object([
                "threadId": .string(id),
                "includeTurns": .bool(false),
            ]),
            as: ThreadReadResult.self
        )
        return result.thread
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

    static func makeProjectlessDirectory(
        for prompt: String,
        root: URL? = nil,
        now: Date = Date(),
        fileManager: FileManager = .default
    ) throws -> String {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .current
        let components = calendar.dateComponents(
            [.year, .month, .day],
            from: now
        )
        let date = String(
            format: "%04d-%02d-%02d",
            components.year ?? 0,
            components.month ?? 0,
            components.day ?? 0
        )
        let base = root
            ?? fileManager.homeDirectoryForCurrentUser
                .appending(path: "Documents/Codex")
        let dateDirectory = base.appending(
            path: date,
            directoryHint: .isDirectory
        )
        try fileManager.createDirectory(
            at: dateDirectory,
            withIntermediateDirectories: true
        )

        let words = prompt.lowercased()
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { !$0.isEmpty }
        let readableSlug = words.prefix(8).joined(separator: "-")
        let slug = String(
            (readableSlug.isEmpty ? "relay-task" : readableSlug).prefix(48)
        )

        for suffix in 1...1_000 {
            let name = suffix == 1 ? slug : "\(slug)-\(suffix)"
            let candidate = dateDirectory.appending(
                path: name,
                directoryHint: .isDirectory
            )
            guard !fileManager.fileExists(atPath: candidate.path) else {
                continue
            }
            try fileManager.createDirectory(
                at: candidate,
                withIntermediateDirectories: false
            )
            return candidate.path
        }

        throw CocoaError(.fileWriteFileExists)
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
    let nextCursor: String?
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
    let path: String?
    let updatedAt: Int
    let status: StatusRecord
    let turns: [TurnRecord]

    init(_ thread: CodexThread) {
        id = thread.id
        name = thread.name
        preview = thread.preview
        cwd = thread.cwd
        path = nil
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

private enum TurnStatus: Decodable, Equatable {
    case completed
    case interrupted
    case failed
    case inProgress
    case unknown(String)

    init(from decoder: any Decoder) throws {
        let value = try decoder.singleValueContainer().decode(String.self)
        self = switch value {
        case "completed": .completed
        case "interrupted": .interrupted
        case "failed": .failed
        case "inProgress": .inProgress
        default: .unknown(value)
        }
    }
}
