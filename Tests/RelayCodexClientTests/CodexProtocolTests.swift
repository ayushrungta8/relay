import Foundation
import Testing
@testable import RelayCodexClient

struct CodexProtocolTests {
    @Test
    func buildsTheMinimalHandshakeAndThreadListMessages() throws {
        let initialize = try object(
            from: CodexProtocol.initializeRequest(id: 1)
        )
        #expect(initialize["id"] as? Int == 1)
        #expect(initialize["method"] as? String == "initialize")

        let initializeParams = try #require(
            initialize["params"] as? [String: Any]
        )
        let clientInfo = try #require(
            initializeParams["clientInfo"] as? [String: Any]
        )
        #expect(clientInfo["name"] as? String == "relay")
        #expect(clientInfo["title"] as? String == "Relay")

        let capabilities = try #require(
            initializeParams["capabilities"] as? [String: Any]
        )
        #expect(capabilities["experimentalApi"] as? Bool == true)

        let initialized = try object(
            from: CodexProtocol.initializedNotification()
        )
        #expect(initialized["id"] == nil)
        #expect(initialized["method"] as? String == "initialized")

        let threadList = try object(
            from: CodexProtocol.threadListRequest(id: 2, limit: 25)
        )
        #expect(threadList["id"] as? Int == 2)
        #expect(threadList["method"] as? String == "thread/list")

        let listParams = try #require(
            threadList["params"] as? [String: Any]
        )
        #expect(listParams["archived"] as? Bool == false)
        #expect(listParams["limit"] as? Int == 25)
    }

    private func object(from data: Data) throws -> [String: Any] {
        try #require(
            JSONSerialization.jsonObject(with: data) as? [String: Any]
        )
    }
}
