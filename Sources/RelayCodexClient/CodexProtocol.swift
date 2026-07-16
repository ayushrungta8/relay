import Foundation

public enum CodexProtocol {
    public static func initializeRequest(id: Int) throws -> Data {
        try encode(
            Request(
                id: id,
                method: "initialize",
                params: InitializeParameters(
                    clientInfo: ClientInfo(
                        name: "relay",
                        title: "Relay",
                        version: "0.1.0"
                    ),
                    capabilities: Capabilities(experimentalApi: true)
                )
            )
        )
    }

    public static func initializedNotification() throws -> Data {
        try encode(Notification(method: "initialized"))
    }

    public static func threadListRequest(id: Int, limit: Int) throws -> Data {
        try encode(
            Request(
                id: id,
                method: "thread/list",
                params: ThreadListParameters(
                    archived: false,
                    limit: limit
                )
            )
        )
    }

    private static func encode<Value: Encodable>(_ value: Value) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        return try encoder.encode(value)
    }
}

private struct Request<Parameters: Encodable>: Encodable {
    let id: Int
    let method: String
    let params: Parameters
}

private struct Notification: Encodable {
    let method: String
}

private struct InitializeParameters: Encodable {
    let clientInfo: ClientInfo
    let capabilities: Capabilities
}

private struct ClientInfo: Encodable {
    let name: String
    let title: String
    let version: String
}

private struct Capabilities: Encodable {
    let experimentalApi: Bool
}

private struct ThreadListParameters: Encodable {
    let archived: Bool
    let limit: Int
}
