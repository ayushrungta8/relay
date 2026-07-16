import Foundation
import RelayCore

public actor CodexAppServerClient {
    private let transport: any CodexAppServerTransport

    public init(transport: any CodexAppServerTransport) {
        self.transport = transport
    }

    public init(executableURL: URL? = nil) {
        transport = StdioCodexAppServerTransport(
            executableURL: executableURL
        )
    }

    public func loadThreads(limit: Int = 25) async throws -> [CodexThread] {
        try await loadThreads(limit: limit, timeout: .seconds(8))
    }

    public func loadThreads(
        limit: Int,
        timeout: Duration
    ) async throws -> [CodexThread] {
        guard limit > 0 else { throw CodexClientError.invalidLimit }

        let transport = transport
        return try await withTaskCancellationHandler {
            try await loadThreads(
                limit: limit,
                timeout: timeout,
                transport: transport
            )
        } onCancel: {
            Task {
                await transport.stop()
            }
        }
    }

    private func loadThreads(
        limit: Int,
        timeout: Duration,
        transport: any CodexAppServerTransport
    ) async throws -> [CodexThread] {
        let frames = try await transport.start()
        let timeoutState = TimeoutState()
        let timeoutTask = Task {
            do {
                try await Task.sleep(for: timeout)
            } catch {
                return
            }
            guard !Task.isCancelled else { return }
            await timeoutState.markTimedOut()
            await transport.stop()
        }

        do {
            try await transport.send(
                CodexProtocol.initializeRequest(id: 1)
            )

            for try await frame in frames {
                guard let responseID = try responseID(in: frame) else {
                    continue
                }

                if let error = try rpcError(in: frame) {
                    throw CodexClientError.rpc(
                        code: error.code,
                        message: error.message
                    )
                }

                switch responseID {
                case 1:
                    try await transport.send(
                        CodexProtocol.initializedNotification()
                    )
                    try await transport.send(
                        CodexProtocol.threadListRequest(
                            id: 2,
                            limit: limit
                        )
                    )
                case 2:
                    let response = try JSONDecoder().decode(
                        CodexThreadListEnvelope.self,
                        from: frame
                    )
                    timeoutTask.cancel()
                    await transport.stop()
                    return response.result.data
                default:
                    continue
                }
            }

            timeoutTask.cancel()
            let didTimeOut = await timeoutState.didTimeOut
            await transport.stop()
            throw didTimeOut
                ? CodexClientError.timedOut
                : CodexClientError.transportClosed
        } catch {
            timeoutTask.cancel()
            let didTimeOut = await timeoutState.didTimeOut
            await transport.stop()
            if didTimeOut {
                throw CodexClientError.timedOut
            }
            throw error
        }
    }

    private func responseID(in data: Data) throws -> Int? {
        guard let object = try JSONSerialization.jsonObject(with: data)
            as? [String: Any] else {
            throw CodexClientError.malformedResponse
        }
        return object["id"] as? Int
    }

    private func rpcError(in data: Data) throws -> RPCError? {
        guard let object = try JSONSerialization.jsonObject(with: data)
            as? [String: Any] else {
            throw CodexClientError.malformedResponse
        }
        guard let error = object["error"] as? [String: Any] else {
            return nil
        }
        guard let code = error["code"] as? Int,
              let message = error["message"] as? String else {
            throw CodexClientError.malformedResponse
        }
        return RPCError(code: code, message: message)
    }
}

private struct RPCError {
    let code: Int
    let message: String
}

private actor TimeoutState {
    private(set) var didTimeOut = false

    func markTimedOut() {
        didTimeOut = true
    }
}
