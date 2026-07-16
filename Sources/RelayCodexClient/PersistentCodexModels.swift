import Foundation

public enum PersistentCodexClientState: Sendable, Equatable {
    case idle
    case starting
    case ready
    case stopping
    case stopped
    case failed(String)
}

public struct CodexServerRequest: Sendable, Equatable {
    public let id: JSONRPCRequestID
    public let method: String
    public let params: JSONValue?

    public init(
        id: JSONRPCRequestID,
        method: String,
        params: JSONValue?
    ) {
        self.id = id
        self.method = method
        self.params = params
    }
}

public enum CodexServerEvent: Sendable, Equatable {
    case lifecycle(PersistentCodexClientState)
    case serverRequest(CodexServerRequest)
    case notification(method: String, params: JSONValue?)
    case protocolIssue(String)
}
