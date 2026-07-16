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

        let interaction = try await observe(
            request,
            with: broker,
            rpc: rpc
        )

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
        let interaction = try await observe(
            request,
            with: broker,
            rpc: rpc
        )

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
    func concurrentAnswersSendOnlyOneRPCResponse() async throws {
        let rpc = PendingInteractionRPCStub(suspendsResponses: true)
        let broker = RelayPendingInteractionBroker(rpc: rpc)
        let interaction = try await observe(
            questionRequest(
                requestID: "concurrent",
                threadID: "worker-concurrent"
            ),
            with: broker,
            rpc: rpc
        )

        async let first: Void = broker.submitAnswers(
            interactionID: interaction.id,
            answers: ["choice": ["A"]]
        )
        await waitForResponseCount(1, rpc: rpc)

        await #expect(
            throws: RelayPendingInteractionBrokerError.submissionInProgress
        ) {
            try await broker.submitAnswers(
                interactionID: interaction.id,
                answers: ["choice": ["B"]]
            )
        }
        await rpc.resolveNextResponse(.success(()))
        try await first

        #expect(await rpc.responseCallCount() == 1)
        #expect(await broker.interaction(id: interaction.id) == nil)
    }

    @Test
    func suspendedOldResponseCannotRemoveNewSameIdentityAfterReconnect()
        async throws
    {
        let rpc = PendingInteractionRPCStub(suspendsResponses: true)
        let broker = RelayPendingInteractionBroker(rpc: rpc)
        let request = questionRequest(
            requestID: "reused",
            threadID: "worker-reused"
        )
        let old = try await observe(request, with: broker, rpc: rpc)

        async let oldSubmission: Void = broker.submitAnswers(
            interactionID: old.id,
            answers: ["choice": ["old"]]
        )
        await waitForResponseCount(1, rpc: rpc)
        await rpc.emit(.lifecycle(.failed("Disconnected")))
        await waitForInteraction(nil, id: old.id, broker: broker)

        let replacement = try await observe(request, with: broker, rpc: rpc)
        #expect(replacement.id == old.id)
        await rpc.resolveNextResponse(.success(()))
        try await oldSubmission

        #expect(await broker.interaction(id: replacement.id) == replacement)
    }

    @Test
    func responseFailureRestoresOnlyTheMatchingLiveRecordForRetry()
        async throws
    {
        let rpc = PendingInteractionRPCStub(failuresRemaining: 1)
        let broker = RelayPendingInteractionBroker(rpc: rpc)
        let interaction = try await observe(
            questionRequest(
                requestID: "retry",
                threadID: "worker-retry"
            ),
            with: broker,
            rpc: rpc
        )

        await #expect(throws: PendingInteractionFixtureError.offline) {
            try await broker.submitAnswers(
                interactionID: interaction.id,
                answers: ["choice": ["A"]]
            )
        }
        #expect(await broker.interaction(id: interaction.id) == interaction)

        try await broker.submitAnswers(
            interactionID: interaction.id,
            answers: ["choice": ["B"]]
        )
        #expect(await rpc.responseCallCount() == 2)
        #expect(await broker.interaction(id: interaction.id) == nil)
    }

    @Test
    func failedOldResponseCannotRestoreOverReplacementGeneration()
        async throws
    {
        let rpc = PendingInteractionRPCStub(suspendsResponses: true)
        let broker = RelayPendingInteractionBroker(rpc: rpc)
        let request = questionRequest(
            requestID: "reused-failure",
            threadID: "worker-reused-failure"
        )
        let old = try await observe(request, with: broker, rpc: rpc)

        let oldTask = Task {
            try await broker.submitAnswers(
                interactionID: old.id,
                answers: ["choice": ["old"]]
            )
        }
        await waitForResponseCount(1, rpc: rpc)
        await rpc.emit(.lifecycle(.failed("Disconnected")))
        await waitForInteraction(nil, id: old.id, broker: broker)
        let replacement = try await observe(request, with: broker, rpc: rpc)

        await rpc.resolveNextResponse(
            .failure(PendingInteractionFixtureError.offline)
        )
        await #expect(throws: PendingInteractionFixtureError.offline) {
            try await oldTask.value
        }
        #expect(await broker.interaction(id: replacement.id) == replacement)

        await rpc.setSuspendsResponses(false)
        try await broker.submitAnswers(
            interactionID: replacement.id,
            answers: ["choice": ["new"]]
        )
        #expect(await broker.interaction(id: replacement.id) == nil)
    }

    @Test
    func preservesEverySameThreadInteractionInArrivalOrder() async throws {
        let rpc = PendingInteractionRPCStub()
        let broker = RelayPendingInteractionBroker(rpc: rpc)
        let first = questionRequest(
            requestID: "z-first",
            threadID: "parallel-worker",
            itemID: "first"
        )
        let second = questionRequest(
            requestID: "a-second",
            threadID: "parallel-worker",
            itemID: "second"
        )

        let firstInteraction = try await observe(first, with: broker, rpc: rpc)
        let secondInteraction = try await observe(second, with: broker, rpc: rpc)

        #expect(
            await broker.interactions().map(\.id)
                == [firstInteraction.id, secondInteraction.id]
        )
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
    private var failuresRemaining: Int
    private var suspendsResponses: Bool
    private var responseCalls = 0
    private var responseContinuations:
        [CheckedContinuation<Void, any Error>] = []

    init(
        failsStart: Bool = false,
        failuresRemaining: Int = 0,
        suspendsResponses: Bool = false
    ) {
        let pair = AsyncStream<CodexServerEvent>.makeStream()
        events = pair.stream
        continuation = pair.continuation
        self.failsStart = failsStart
        self.failuresRemaining = failuresRemaining
        self.suspendsResponses = suspendsResponses
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
        responseCalls += 1
        if suspendsResponses {
            try await withCheckedThrowingContinuation { continuation in
                responseContinuations.append(continuation)
            }
        }
        if failuresRemaining > 0 {
            failuresRemaining -= 1
            throw PendingInteractionFixtureError.offline
        }
        responses[requestID] = result
    }

    func response(to id: JSONRPCRequestID) -> JSONValue? {
        responses[id]
    }

    func emit(_ event: CodexServerEvent) {
        continuation.yield(event)
    }

    func responseCallCount() -> Int { responseCalls }

    func resolveNextResponse(_ result: Result<Void, any Error>) {
        guard !responseContinuations.isEmpty else { return }
        responseContinuations.removeFirst().resume(with: result)
    }

    func setSuspendsResponses(_ value: Bool) {
        suspendsResponses = value
    }
}

private enum PendingInteractionFixtureError: Error {
    case offline
}

private func observe(
    _ request: CodexServerRequest,
    with broker: RelayPendingInteractionBroker,
    rpc: PendingInteractionRPCStub
) async throws -> RelayPendingInteraction {
    try await broker.start()
    await rpc.emit(.serverRequest(request))
    let expectedID = interactionID(for: request)
    for _ in 0..<200
    where await broker.interaction(id: expectedID) == nil {
        await Task.yield()
    }
    return try #require(await broker.interaction(id: expectedID))
}

private func questionRequest(
    requestID: String,
    threadID: String,
    itemID: String = "item"
) -> CodexServerRequest {
    CodexServerRequest(
        id: .string(requestID),
        method: "item/tool/requestUserInput",
        params: .object([
            "threadId": .string(threadID),
            "turnId": .string("turn"),
            "itemId": .string(itemID),
            "questions": .array([
                .object([
                    "id": .string("choice"),
                    "header": .string("Choice"),
                    "question": .string("Choose?"),
                ]),
            ]),
        ])
    )
}

private func interactionID(for request: CodexServerRequest) -> String {
    let threadID = request.params?["threadId"]?.stringValue
        ?? request.params?["conversationId"]?.stringValue
        ?? ""
    let itemID = request.params?["itemId"]?.stringValue ?? ""
    let requestID = switch request.id {
    case let .string(value): value
    case let .integer(value): String(value)
    }
    return "\(threadID):\(itemID):\(requestID)"
}

private func waitForResponseCount(
    _ count: Int,
    rpc: PendingInteractionRPCStub
) async {
    for _ in 0..<200 where await rpc.responseCallCount() < count {
        await Task.yield()
    }
}

private func waitForInteraction(
    _ expected: RelayPendingInteraction?,
    id: String,
    broker: RelayPendingInteractionBroker
) async {
    for _ in 0..<200
    where await broker.interaction(id: id) != expected {
        await Task.yield()
    }
}
