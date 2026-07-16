import Foundation
import RelayCore
import Testing
@testable import RelayCodexClient

struct CodexAppServerClientTests {
    @Test
    func handshakesThenLoadsRealCodexThreads() async throws {
        let transport = ScriptedTransport()
        let client = CodexAppServerClient(transport: transport)

        let threads = try await client.loadThreads(limit: 10)

        let thread = try #require(threads.first)
        #expect(thread.id == "thread-1")
        #expect(thread.preview == "Build Relay")
        #expect(thread.status == .idle)
        #expect(
            await transport.recordedMethods()
                == ["initialize", "initialized", "thread/list"]
        )
        #expect(await transport.wasStopped())
    }

    @Test
    func timesOutAndStopsAnUnresponsiveAppServer() async {
        let transport = SilentTransport()
        let client = CodexAppServerClient(transport: transport)

        do {
            _ = try await client.loadThreads(
                limit: 10,
                timeout: .milliseconds(40)
            )
            Issue.record("Expected the request to time out")
        } catch let error as CodexClientError {
            guard case .timedOut = error else {
                Issue.record("Unexpected error: \(error)")
                return
            }
        } catch {
            Issue.record("Unexpected error: \(error)")
        }

        #expect(await transport.wasStopped())
    }
}

private actor ScriptedTransport: CodexAppServerTransport {
    private let pair = AsyncThrowingStream<Data, any Error>.makeStream(
        bufferingPolicy: .unbounded
    )
    private var methods: [String] = []
    private var stopped = false

    func start() async throws -> AsyncThrowingStream<Data, any Error> {
        pair.stream
    }

    func send(_ message: Data) async throws {
        let object = try #require(
            JSONSerialization.jsonObject(with: message) as? [String: Any]
        )
        let method = try #require(object["method"] as? String)
        methods.append(method)

        switch method {
        case "initialize":
            try emit([
                "id": 1,
                "result": [
                    "userAgent": "codex-test",
                    "platformFamily": "unix",
                    "platformOs": "macos",
                    "codexHome": "/tmp/.codex",
                ],
            ])
        case "thread/list":
            try emit([
                "id": 2,
                "result": [
                    "data": [
                        [
                            "id": "thread-1",
                            "preview": "Build Relay",
                            "cwd": "/Users/ayushrungta/Work/Relay",
                            "updatedAt": 1_784_210_400,
                            "status": ["type": "idle"],
                        ],
                    ],
                    "nextCursor": NSNull(),
                ],
            ])
        case "initialized":
            break
        default:
            Issue.record("Unexpected method: \(method)")
        }
    }

    func stop() async {
        stopped = true
        pair.continuation.finish()
    }

    func recordedMethods() -> [String] {
        methods
    }

    func wasStopped() -> Bool {
        stopped
    }

    private func emit(_ object: [String: Any]) throws {
        pair.continuation.yield(
            try JSONSerialization.data(withJSONObject: object)
        )
    }
}

private actor SilentTransport: CodexAppServerTransport {
    private let pair = AsyncThrowingStream<Data, any Error>.makeStream(
        bufferingPolicy: .unbounded
    )
    private var stopped = false

    func start() async throws -> AsyncThrowingStream<Data, any Error> {
        pair.stream
    }

    func send(_ message: Data) async throws {}

    func stop() async {
        stopped = true
        pair.continuation.finish()
    }

    func wasStopped() -> Bool {
        stopped
    }
}
