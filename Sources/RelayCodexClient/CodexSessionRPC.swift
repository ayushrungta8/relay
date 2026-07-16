import Foundation

public protocol CodexSessionRPC: CodexRPCRequesting {
    var events: AsyncStream<CodexServerEvent> { get }

    func start() async throws
    func stop() async
    func respond(
        to requestID: JSONRPCRequestID,
        result: JSONValue
    ) async throws
}

extension PersistentCodexAppServerClient: CodexSessionRPC {}
