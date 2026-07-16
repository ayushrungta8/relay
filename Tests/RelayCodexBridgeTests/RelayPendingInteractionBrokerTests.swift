import Foundation
import RelayCodexBridge
import RelayCodexClient
import RelayCore
import Testing

struct RelayPendingInteractionBrokerTests {
    @Test
    func retainsFullOwnedQuestionsAndAnswersTheOriginalRequest() async throws {
        let rpc = PendingInteractionRPCStub()
        let broker = RelayPendingInteractionBroker(rpc: rpc)
        let request = CodexServerRequest(
            id: .string("request-7"),
            method: "item/tool/requestUserInput",
            params: .object([
                "threadId": .string("worker-1"),
                "turnId": .string("turn-1"),
                "itemId": .string("item-1"),
                "questions": .array([
                    .object([
                        "id": .string("database"),
                        "header": .string("Database"),
                        "question": .string("Which database should Relay use?"),
                        "isOther": .bool(true),
                        "options": .array([
                            .object([
                                "label": .string("SQLite"),
                                "description": .string("Keep state on this Mac."),
                            ]),
                            .object([
                                "label": .string("Postgres"),
                                "description": .string("Share state remotely."),
                            ]),
                        ]),
                    ]),
                    .object([
                        "id": .string("name"),
                        "header": .string("Name"),
                        "question": .string("What should the database be called?"),
                        "isSecret": .bool(false),
                    ]),
                ]),
            ])
        )

        let interaction = try #require(await broker.retain(request))

        #expect(interaction.threadID == "worker-1")
        guard case let .questions(questions) = interaction.kind else {
            Issue.record("Expected a question interaction")
            return
        }
        #expect(questions.count == 2)
        #expect(questions[0].id == "database")
        #expect(questions[0].allowsOther)
        #expect(questions[0].options.map(\.label) == ["SQLite", "Postgres"])
        #expect(questions[0].options[1].description == "Share state remotely.")

        try await broker.submitAnswers(
            interactionID: interaction.id,
            answers: [
                "database": ["SQLite"],
                "name": ["relay-local"],
            ]
        )

        let response = try #require(
            await rpc.response(to: .string("request-7"))?.objectValue
        )
        let answers = try #require(response["answers"]?.objectValue)
        #expect(
            answers["database"]?["answers"]?.arrayValue
                == [.string("SQLite")]
        )
        #expect(
            answers["name"]?["answers"]?.arrayValue
                == [.string("relay-local")]
        )
        #expect(await broker.interaction(id: interaction.id) == nil)
    }

    @Test(
        arguments: [
            (
                "item/commandExecution/requestApproval",
                RelayPendingApprovalDecision.approve,
                "accept"
            ),
            (
                "item/commandExecution/requestApproval",
                RelayPendingApprovalDecision.decline,
                "decline"
            ),
            (
                "applyPatchApproval",
                RelayPendingApprovalDecision.approve,
                "approved"
            ),
            (
                "execCommandApproval",
                RelayPendingApprovalDecision.decline,
                "denied"
            ),
        ]
    )
    func usesOnlyTheDecisionValuesSupportedByEachApprovalProtocol(
        method: String,
        decision: RelayPendingApprovalDecision,
        expectedValue: String
    ) async throws {
        let rpc = PendingInteractionRPCStub()
        let broker = RelayPendingInteractionBroker(rpc: rpc)
        let request = CodexServerRequest(
            id: .string("approval-request"),
            method: method,
            params: .object([
                method == "applyPatchApproval" || method == "execCommandApproval"
                    ? "conversationId" : "threadId": .string("worker-2"),
                "turnId": .string("turn-2"),
                "itemId": .string("item-2"),
                "reason": .string("Needs write access."),
                "command": .string("swift test"),
            ])
        )
        let interaction = try #require(await broker.retain(request))

        try await broker.submitDecision(
            interactionID: interaction.id,
            decision: decision
        )

        let response = try #require(
            await rpc.response(to: .string("approval-request"))?.objectValue
        )
        #expect(response["decision"] == .string(expectedValue))
    }

    @Test
    func clearsUnanswerableOwnedRequestsWhenTheConnectionFails() async throws {
        let rpc = PendingInteractionRPCStub()
        let broker = RelayPendingInteractionBroker(rpc: rpc)
        try await broker.start()
        await rpc.emit(
            .serverRequest(
                CodexServerRequest(
                    id: .string("will-disconnect"),
                    method: "item/tool/requestUserInput",
                    params: .object([
                        "threadId": .string("worker-disconnected"),
                        "turnId": .string("turn"),
                        "itemId": .string("item"),
                        "questions": .array([
                            .object([
                                "id": .string("choice"),
                                "header": .string("Choice"),
                                "question": .string("Choose?"),
                            ]),
                        ]),
                    ])
                )
            )
        )
        for _ in 0..<100
        where await broker.interaction(threadID: "worker-disconnected") == nil {
            await Task.yield()
        }
        #expect(await broker.interaction(threadID: "worker-disconnected") != nil)

        await rpc.emit(.lifecycle(.failed("Disconnected")))
        for _ in 0..<100
        where await broker.interaction(threadID: "worker-disconnected") != nil {
            await Task.yield()
        }

        #expect(await broker.interaction(threadID: "worker-disconnected") == nil)
    }

    @Test
    func keepsObservingTheSharedStreamWhenInitialConnectionFails() async {
        let rpc = PendingInteractionRPCStub(failsStart: true)
        let broker = RelayPendingInteractionBroker(rpc: rpc)

        await #expect(throws: PendingInteractionFixtureError.offline) {
            try await broker.start()
        }
        await rpc.emit(
            .serverRequest(
                CodexServerRequest(
                    id: .string("after-reconnect"),
                    method: "item/tool/requestUserInput",
                    params: .object([
                        "threadId": .string("worker-reconnected"),
                        "turnId": .string("turn"),
                        "itemId": .string("item"),
                        "questions": .array([
                            .object([
                                "id": .string("choice"),
                                "header": .string("Choice"),
                                "question": .string("Choose?"),
                            ]),
                        ]),
                    ])
                )
            )
        )
        for _ in 0..<100
        where await broker.interaction(threadID: "worker-reconnected") == nil {
            await Task.yield()
        }

        #expect(await broker.interaction(threadID: "worker-reconnected") != nil)
    }

    @Test
    func doesNotClaimOwnershipOfAnUnobservedExternalRequest() async {
        let broker = RelayPendingInteractionBroker(
            rpc: PendingInteractionRPCStub()
        )

        #expect(await broker.interaction(threadID: "external-worker") == nil)
    }
}

private actor PendingInteractionRPCStub: CodexSessionRPC {
    nonisolated let events: AsyncStream<CodexServerEvent>
    private let continuation: AsyncStream<CodexServerEvent>.Continuation
    private var responses: [JSONRPCRequestID: JSONValue] = [:]
    private let failsStart: Bool

    init(failsStart: Bool = false) {
        let pair = AsyncStream<CodexServerEvent>.makeStream()
        events = pair.stream
        continuation = pair.continuation
        self.failsStart = failsStart
    }

    func start() async throws {
        if failsStart { throw PendingInteractionFixtureError.offline }
    }
    func stop() async { continuation.finish() }

    func requestJSON(
        method: String,
        params: JSONValue,
        timeout: Duration
    ) async throws -> JSONValue {
        .object([:])
    }

    func respond(
        to requestID: JSONRPCRequestID,
        result: JSONValue
    ) async throws {
        responses[requestID] = result
    }

    func response(to id: JSONRPCRequestID) -> JSONValue? {
        responses[id]
    }

    func emit(_ event: CodexServerEvent) {
        continuation.yield(event)
    }
}

private enum PendingInteractionFixtureError: Error {
    case offline
}
