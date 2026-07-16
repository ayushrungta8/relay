import Foundation
import Testing
@testable import RelayCodexClient

struct PersistentCodexAppServerClientTests {
    @Test
    func handshakesCorrelatesResponsesAndRoutesServerRequests() async throws {
        let transport = PersistentScriptedTransport()
        let client = PersistentCodexAppServerClient(transport: transport)

        try await client.start()

        let response: EmptyThreadList = try await client.request(
            method: "thread/list",
            params: EmptyThreadListParams(limit: 5)
        )
        #expect(response.data.isEmpty)

        let requestTask = Task { () -> CodexServerRequest? in
            for await event in client.events {
                if case let .serverRequest(request) = event {
                    return request
                }
            }
            return nil
        }

        await transport.emit(
            .object([
                "id": .string("tool-call-1"),
                "method": .string("item/tool/call"),
                "params": .object([
                    "threadId": .string("controller-thread"),
                    "turnId": .string("turn-1"),
                    "callId": .string("call-1"),
                    "tool": .string("relay_list_tasks"),
                    "arguments": .object([:]),
                ]),
            ])
        )

        let serverRequest = try #require(await requestTask.value)
        #expect(serverRequest.method == "item/tool/call")
        #expect(serverRequest.params?["tool"]?.stringValue == "relay_list_tasks")

        try await client.respond(
            to: serverRequest.id,
            result: .object([
                "success": .bool(true),
                "contentItems": .array([]),
            ])
        )

        let methods = await transport.recordedMethods()
        #expect(methods == ["initialize", "initialized", "thread/list"])
        #expect(await transport.recordedResponseIDs() == ["tool-call-1"])

        await client.stop()
    }

    @Test
    func restartsTheSamePersistentClientAfterTransportFailure() async throws {
        let transport = RestartablePersistentTransport()
        let client = PersistentCodexAppServerClient(transport: transport)

        try await client.start()
        await transport.failCurrentConnection()

        for await event in client.events {
            guard case .lifecycle(.failed) = event else { continue }
            break
        }

        try await client.start()

        #expect(await transport.startCount() == 2)
        #expect(await client.state == .ready)
        await client.stop()
    }

    @Test
    func startingAnAlreadyReadyPersistentClientIsIdempotent() async throws {
        let transport = RestartablePersistentTransport()
        let client = PersistentCodexAppServerClient(transport: transport)

        try await client.start()
        try await client.start()

        #expect(await transport.startCount() == 1)
        await client.stop()
    }

    @Test
    func broadcastsServerEventsToEverySubscriber() async throws {
        let transport = RestartablePersistentTransport()
        let client = PersistentCodexAppServerClient(transport: transport)
        var first = client.events.makeAsyncIterator()
        var second = client.events.makeAsyncIterator()

        try await client.start()

        #expect(await first.next() == .lifecycle(.starting))
        #expect(await second.next() == .lifecycle(.starting))
        await client.stop()
    }
}

private struct EmptyThreadListParams: Encodable, Sendable {
    let limit: Int
}

private struct EmptyThreadList: Decodable, Sendable {
    let data: [String]
}

private actor PersistentScriptedTransport: CodexAppServerTransport {
    private let pair = AsyncThrowingStream<Data, any Error>.makeStream(
        bufferingPolicy: .unbounded
    )
    private var messages: [[String: JSONValue]] = []

    func start() async throws -> AsyncThrowingStream<Data, any Error> {
        pair.stream
    }

    func send(_ message: Data) async throws {
        let value = try JSONDecoder().decode(JSONValue.self, from: message)
        let object = try #require(value.objectValue)
        messages.append(object)

        guard let method = object["method"]?.stringValue,
              let id = object["id"] else {
            return
        }

        switch method {
        case "initialize":
            emitNow(
                .object([
                    "id": id,
                    "result": .object([
                        "userAgent": .string("fixture"),
                        "platformFamily": .string("unix"),
                        "platformOs": .string("macos"),
                        "codexHome": .string("/tmp/.codex"),
                    ]),
                ])
            )
        case "thread/list":
            emitNow(
                .object([
                    "id": id,
                    "result": .object(["data": .array([])]),
                ])
            )
        default:
            break
        }
    }

    func stop() async {
        pair.continuation.finish()
    }

    func emit(_ value: JSONValue) {
        emitNow(value)
    }

    func recordedMethods() -> [String] {
        messages.compactMap { $0["method"]?.stringValue }
    }

    func recordedResponseIDs() -> [String] {
        messages.compactMap { message in
            guard message["method"] == nil else { return nil }
            return message["id"]?.stringValue
        }
    }

    private func emitNow(_ value: JSONValue) {
        guard let data = try? JSONEncoder().encode(value) else {
            Issue.record("Could not encode fixture response")
            return
        }
        pair.continuation.yield(data)
    }
}

private actor RestartablePersistentTransport: CodexAppServerTransport {
    private var starts = 0
    private var continuation:
        AsyncThrowingStream<Data, any Error>.Continuation?

    func start() async throws -> AsyncThrowingStream<Data, any Error> {
        starts += 1
        let pair = AsyncThrowingStream<Data, any Error>.makeStream(
            bufferingPolicy: .unbounded
        )
        continuation = pair.continuation
        return pair.stream
    }

    func send(_ message: Data) async throws {
        let value = try JSONDecoder().decode(JSONValue.self, from: message)
        guard let object = value.objectValue,
              object["method"]?.stringValue == "initialize",
              let id = object["id"] else {
            return
        }
        emit(
            .object([
                "id": id,
                "result": .object([
                    "userAgent": .string("fixture"),
                    "platformFamily": .string("unix"),
                    "platformOs": .string("macos"),
                    "codexHome": .string("/tmp/.codex"),
                ]),
            ])
        )
    }

    func stop() async {
        continuation?.finish()
        continuation = nil
    }

    func failCurrentConnection() {
        continuation?.finish(throwing: StoreTransportFailure.closed)
    }

    func startCount() -> Int {
        starts
    }

    private func emit(_ value: JSONValue) {
        guard let data = try? JSONEncoder().encode(value) else { return }
        continuation?.yield(data)
    }
}

private enum StoreTransportFailure: Error {
    case closed
}
