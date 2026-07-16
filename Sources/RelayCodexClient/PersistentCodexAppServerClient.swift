import Foundation

public actor PersistentCodexAppServerClient {
    public nonisolated var events: AsyncStream<CodexServerEvent> {
        eventBroadcaster.stream()
    }

    private let transport: any CodexAppServerTransport
    private nonisolated let eventBroadcaster = CodexServerEventBroadcaster()
    private var receiveTask: Task<Void, Never>?
    private var pending: [
        JSONRPCRequestID:
            AsyncThrowingStream<JSONValue, any Error>.Continuation
    ] = [:]
    private var nextRequestID: Int64 = 1

    public private(set) var state: PersistentCodexClientState = .idle

    public init(transport: any CodexAppServerTransport) {
        self.transport = transport
    }

    public init(executableURL: URL? = nil) {
        transport = StdioCodexAppServerTransport(
            executableURL: executableURL
        )
    }

    deinit {
        receiveTask?.cancel()
        eventBroadcaster.finish()
    }

    public func start() async throws {
        switch state {
        case .idle, .failed:
            break
        case .ready:
            return
        default:
            throw CodexClientError.invalidState(
                "The persistent Codex client is already running or stopped."
            )
        }

        setState(.starting)

        do {
            let frames = try await transport.start()
            receiveTask = Task { [weak self] in
                do {
                    for try await frame in frames {
                        guard let self else { return }
                        await self.receive(frame)
                    }
                    await self?.transportEnded(
                        error: CodexClientError.transportClosed
                    )
                } catch {
                    await self?.transportEnded(error: error)
                }
            }

            let _: JSONValue = try await request(
                method: "initialize",
                params: InitializeParameters(
                    clientInfo: ClientInfo(
                        name: "relay",
                        title: "Relay",
                        version: "0.1.0"
                    ),
                    capabilities: Capabilities(experimentalApi: true)
                ),
                permitsStartingState: true
            )
            try await sendNotificationUnchecked(
                method: "initialized",
                params: nil
            )
            setState(.ready)
        } catch {
            receiveTask?.cancel()
            receiveTask = nil
            await transport.stop()
            failAllPending(with: error)
            setState(.failed(error.localizedDescription))
            throw error
        }
    }

    public func stop() async {
        switch state {
        case .stopped, .stopping:
            return
        default:
            break
        }

        setState(.stopping)
        receiveTask?.cancel()
        receiveTask = nil
        failAllPending(with: CodexClientError.transportClosed)
        await transport.stop()
        setState(.stopped)
        eventBroadcaster.finish()
    }

    public func request<Parameters, Result>(
        method: String,
        params: Parameters,
        timeout: Duration = .seconds(8)
    ) async throws -> Result
    where
        Parameters: Encodable & Sendable,
        Result: Decodable & Sendable
    {
        try await request(
            method: method,
            params: params,
            timeout: timeout,
            permitsStartingState: false
        )
    }

    public func sendNotification(
        method: String,
        params: JSONValue?
    ) async throws {
        try ensureReady()
        try await sendNotificationUnchecked(
            method: method,
            params: params
        )
    }

    private func sendNotificationUnchecked(
        method: String,
        params: JSONValue?
    ) async throws {
        var object: [String: JSONValue] = [
            "method": .string(method),
        ]
        if let params {
            object["params"] = params
        }
        try await sendObject(object)
    }

    public func respond(
        to requestID: JSONRPCRequestID,
        result: JSONValue
    ) async throws {
        try ensureReady()
        try await sendObject([
            "id": requestID.jsonValue,
            "result": result,
        ])
    }

    private func request<Parameters, Result>(
        method: String,
        params: Parameters,
        timeout: Duration = .seconds(8),
        permitsStartingState: Bool
    ) async throws -> Result
    where
        Parameters: Encodable & Sendable,
        Result: Decodable & Sendable
    {
        if !permitsStartingState {
            try ensureReady()
        }

        let id = JSONRPCRequestID.integer(nextRequestID)
        nextRequestID += 1
        let pair = AsyncThrowingStream<JSONValue, any Error>.makeStream(
            bufferingPolicy: .bufferingNewest(1)
        )
        pending[id] = pair.continuation

        do {
            try await sendObject([
                "id": id.jsonValue,
                "method": .string(method),
                "params": try encodeAsJSONValue(params),
            ])
        } catch {
            pending.removeValue(forKey: id)?.finish(throwing: error)
            throw error
        }

        let timeoutTask = Task { [weak self] in
            do {
                try await Task.sleep(for: timeout)
            } catch {
                return
            }
            await self?.expirePending(id: id)
        }

        return try await withTaskCancellationHandler {
            do {
                for try await value in pair.stream {
                    timeoutTask.cancel()
                    do {
                        return try decode(Result.self, from: value)
                    } catch {
                        throw CodexClientError.responseDecodingFailed(
                            method: method,
                            reason: error.localizedDescription
                        )
                    }
                }
                timeoutTask.cancel()
                throw CodexClientError.transportClosed
            } catch is CancellationError {
                timeoutTask.cancel()
                throw CodexClientError.requestCancelled
            }
        } onCancel: {
            timeoutTask.cancel()
            Task {
                await self.cancelPending(id: id)
            }
        }
    }

    private func ensureReady() throws {
        guard state == .ready else {
            throw CodexClientError.invalidState(
                "The persistent Codex client is not ready."
            )
        }
    }

    private func expirePending(id: JSONRPCRequestID) {
        pending.removeValue(forKey: id)?.finish(
            throwing: CodexClientError.timedOut
        )
    }

    private func cancelPending(id: JSONRPCRequestID) {
        pending.removeValue(forKey: id)?.finish(
            throwing: CodexClientError.requestCancelled
        )
    }

    private func setState(_ newState: PersistentCodexClientState) {
        state = newState
        eventBroadcaster.yield(.lifecycle(newState))
    }

    private func sendObject(_ object: [String: JSONValue]) async throws {
        let data = try JSONEncoder().encode(JSONValue.object(object))
        try await transport.send(data)
    }

    private func receive(_ frame: Data) {
        let value: JSONValue
        do {
            value = try JSONDecoder().decode(JSONValue.self, from: frame)
        } catch {
            eventBroadcaster.yield(
                .protocolIssue(
                    "Invalid JSON frame: \(error.localizedDescription)"
                )
            )
            return
        }

        guard let object = value.objectValue else {
            eventBroadcaster.yield(
                .protocolIssue("Top-level JSON-RPC message is not an object.")
            )
            return
        }

        if let idValue = object["id"],
           let id = JSONRPCRequestID(jsonValue: idValue) {
            if let method = object["method"]?.stringValue {
                eventBroadcaster.yield(
                    .serverRequest(
                        CodexServerRequest(
                            id: id,
                            method: method,
                            params: object["params"]
                        )
                    )
                )
            } else {
                routeResponse(id: id, object: object)
            }
            return
        }

        guard let method = object["method"]?.stringValue else {
            eventBroadcaster.yield(
                .protocolIssue(
                    "Message contains neither a request id nor a method."
                )
            )
            return
        }

        eventBroadcaster.yield(
            .notification(method: method, params: object["params"])
        )
    }

    private func routeResponse(
        id: JSONRPCRequestID,
        object: [String: JSONValue]
    ) {
        guard let continuation = pending.removeValue(forKey: id) else {
            eventBroadcaster.yield(
                .protocolIssue("Response received for an unknown request.")
            )
            return
        }

        if let error = object["error"]?.objectValue,
           let code = error["code"]?.intValue,
           let message = error["message"]?.stringValue {
            continuation.finish(
                throwing: CodexClientError.rpc(
                    code: Int(code),
                    message: message
                )
            )
        } else if let result = object["result"] {
            continuation.yield(result)
            continuation.finish()
        } else {
            continuation.finish(
                throwing: CodexClientError.malformedResponse
            )
        }
    }

    private func transportEnded(error: (any Error)?) async {
        switch state {
        case .stopped, .stopping:
            return
        default:
            break
        }

        let actualError = error ?? CodexClientError.transportClosed
        failAllPending(with: actualError)
        receiveTask = nil
        await transport.stop()
        setState(.failed(actualError.localizedDescription))
    }

    private func failAllPending(with error: any Error) {
        let continuations = pending.values
        pending.removeAll()
        for continuation in continuations {
            continuation.finish(throwing: error)
        }
    }

    private func encodeAsJSONValue<Value: Encodable>(
        _ value: Value
    ) throws -> JSONValue {
        let data = try JSONEncoder().encode(value)
        return try JSONDecoder().decode(JSONValue.self, from: data)
    }

    private func decode<Value: Decodable>(
        _ type: Value.Type,
        from value: JSONValue
    ) throws -> Value {
        let data = try JSONEncoder().encode(value)
        return try JSONDecoder().decode(type, from: data)
    }
}

private struct InitializeParameters: Encodable, Sendable {
    let clientInfo: ClientInfo
    let capabilities: Capabilities
}

private struct ClientInfo: Encodable, Sendable {
    let name: String
    let title: String
    let version: String
}

private struct Capabilities: Encodable, Sendable {
    let experimentalApi: Bool
}

private extension JSONRPCRequestID {
    var jsonValue: JSONValue {
        switch self {
        case let .integer(value):
            .integer(value)
        case let .string(value):
            .string(value)
        }
    }

    init?(jsonValue: JSONValue) {
        switch jsonValue {
        case let .integer(value):
            self = .integer(value)
        case let .string(value):
            self = .string(value)
        default:
            return nil
        }
    }
}
