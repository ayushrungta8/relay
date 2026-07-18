import Foundation
import RelayCore

public actor CodexMonitoringClient {
    private let rpc: any CodexRPCRequesting
    private nonisolated let eventStream: AsyncStream<RelayMonitoringEvent>
    private let eventContinuation:
        AsyncStream<RelayMonitoringEvent>.Continuation
    private nonisolated(unsafe) var eventTask: Task<Void, Never>?
    private var tokenUsageByThreadID: [String: RelayThreadTokenUsage] = [:]
    private var latestUsageSnapshot: RelayUsageSnapshot?

    public init(
        rpc: any CodexRPCRequesting,
        serverEvents: AsyncStream<CodexServerEvent>
    ) {
        let pair = AsyncStream<RelayMonitoringEvent>.makeStream(
            bufferingPolicy: .unbounded
        )
        self.rpc = rpc
        eventStream = pair.stream
        eventContinuation = pair.continuation
        eventTask = Task { [weak self] in
            for await event in serverEvents {
                guard let self else { return }
                await self.receive(event)
            }
        }
    }

    public init(client: PersistentCodexAppServerClient) {
        self.init(rpc: client, serverEvents: client.events)
    }

    deinit {
        eventTask?.cancel()
        eventContinuation.finish()
    }

    public nonisolated func events() -> AsyncStream<RelayMonitoringEvent> {
        eventStream
    }

    public func snapshot(
        limit: Int = 25
    ) async throws -> RelayMonitoringSnapshot {
        let list: CodexMonitoringThreadListResult = try await request(
            method: "thread/list",
            params: .object([
                "archived": .bool(false),
                "limit": .integer(Int64(limit)),
                "sortKey": .string("updated_at"),
            ])
        )

        var tasks: [RelayTaskActivity] = []
        var rolloutUsage: RelayUsageSnapshot?
        tasks.reserveCapacity(list.data.count)
        for listedThread in list.data {
            let read: CodexMonitoringThreadReadResult = try await request(
                method: "thread/read",
                params: .object([
                    "threadId": .string(listedThread.id),
                    "includeTurns": .bool(true),
                ])
            )
            let sessionSnapshot = read.thread.path.flatMap {
                try? CodexSessionLogSnapshot.read(from: URL(filePath: $0))
            }
            tasks.append(
                read.thread.activity(sessionSnapshot: sessionSnapshot)
            )
            if let tokenUsage = sessionSnapshot?.tokenUsage {
                tokenUsageByThreadID[read.thread.id] = tokenUsage
            }
            if let sessionUsage = sessionSnapshot?.usage,
               rolloutUsage == nil {
                rolloutUsage = sessionUsage
            }
        }

        let rateLimits: CodexRateLimitsReadResult = try await request(
            method: "account/rateLimits/read",
            params: .object([:])
        )
        let accountUsage = rateLimits.relaySnapshot
        let usage = rolloutUsage.map {
            accountUsage.mergingSparseUpdate($0)
        } ?? accountUsage
        latestUsageSnapshot = usage
        return RelayMonitoringSnapshot(
            tasks: tasks,
            usage: usage,
            tokenUsageByThreadID: tokenUsageByThreadID
        )
    }

    public func consumeResetCredit(
        creditID: String?
    ) async throws -> CodexResetCreditConsumeOutcome {
        var params: [String: JSONValue] = [
            "idempotencyKey": .string(UUID().uuidString),
        ]
        if let creditID {
            params["creditId"] = .string(creditID)
        }
        let result: CodexResetCreditConsumeResult = try await request(
            method: "account/rateLimitResetCredit/consume",
            params: .object(params)
        )
        return CodexResetCreditConsumeOutcome(rawOutcome: result.outcome)
    }

    private func receive(_ event: CodexServerEvent) {
        switch event {
        case let .notification(method, params):
            receiveNotification(method: method, params: params)
        case let .lifecycle(state):
            eventContinuation.yield(.lifecycle(state))
        case let .protocolIssue(message):
            eventContinuation.yield(.protocolIssue(message))
        case .serverRequest:
            break
        }
    }

    private func receiveNotification(
        method: String,
        params: JSONValue?
    ) {
        guard let params else { return }
        do {
            switch method {
            case "thread/status/changed":
                let value: CodexStatusChangedParameters = try decode(params)
                eventContinuation.yield(
                    .threadStatusChanged(
                        threadID: value.threadID,
                        status: value.status.type,
                        activeFlags: value.status.activeFlags
                    )
                )
            case "thread/tokenUsage/updated":
                let value: CodexTokenUsageUpdatedParameters = try decode(params)
                tokenUsageByThreadID[value.threadID] = value.tokenUsage
                eventContinuation.yield(
                    .threadTokenUsageUpdated(
                        threadID: value.threadID,
                        turnID: value.turnID,
                        usage: value.tokenUsage
                    )
                )
            case "account/rateLimits/updated":
                let value: CodexRateLimitsUpdatedParameters = try decode(params)
                let patch = value.rateLimits.relaySnapshot()
                let usage = latestUsageSnapshot?
                    .mergingSparseUpdate(patch) ?? patch
                latestUsageSnapshot = usage
                eventContinuation.yield(
                    .usageUpdated(usage)
                )
            case "thread/started",
                 "turn/started",
                 "turn/completed",
                 "item/started",
                 "item/completed":
                if let threadID = params["threadId"]?.stringValue {
                    eventContinuation.yield(
                        .taskChanged(threadID: threadID)
                    )
                }
            default:
                break
            }
        } catch {
            eventContinuation.yield(
                .protocolIssue(
                    "Could not decode \(method): \(error.localizedDescription)"
                )
            )
        }
    }

    private func request<Result: Decodable>(
        method: String,
        params: JSONValue
    ) async throws -> Result {
        let value = try await rpc.requestJSON(
            method: method,
            params: params,
            timeout: .seconds(8)
        )
        return try decode(value)
    }

    private func decode<Result: Decodable>(
        _ value: JSONValue
    ) throws -> Result {
        let data = try JSONEncoder().encode(value)
        return try JSONDecoder().decode(Result.self, from: data)
    }
}
