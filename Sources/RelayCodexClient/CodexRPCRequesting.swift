import Foundation

public protocol CodexRPCRequesting: Sendable {
    func requestJSON(
        method: String,
        params: JSONValue,
        timeout: Duration
    ) async throws -> JSONValue
}

extension PersistentCodexAppServerClient: CodexRPCRequesting {
    public func requestJSON(
        method: String,
        params: JSONValue,
        timeout: Duration = .seconds(8)
    ) async throws -> JSONValue {
        let result: JSONValue = try await request(
            method: method,
            params: params,
            timeout: timeout
        )
        return result
    }
}
