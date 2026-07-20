import Foundation
import RelayBrain
import RelayCodexBridge
import RelayCodexClient
import Testing

struct CodexControllerSessionAdapterTests {
    @Test
    func controllerCacheChangesWhenItsBehaviorPromptChanges() {
        #expect(
            RelayControllerThreadFileStore.defaultFileURL.lastPathComponent
            == "controller-thread-id-v7"
        )
    }

    @Test
    func createsAndPersistsAControllerThreadWithDynamicTools() async throws {
        let rpc = ControllerRPCStub()
        let store = ControllerThreadStoreStub()
        let session = CodexControllerSessionAdapter(
            rpc: rpc,
            store: store,
            cwd: "/Users/test/Work"
        )

        let controller = try await session.ensureControllerThread(
            configuration: .default
        )

        #expect(controller.id == "controller-1")
        #expect(await store.loadThreadID() == "controller-1")

        let startParams = try #require(
            await rpc.params(for: "thread/start")?.objectValue
        )
        #expect(startParams["ephemeral"] == .bool(false))
        #expect(startParams["cwd"] == .string("/Users/test/Work"))
        #expect(startParams["model"] == .string("gpt-5.6-luna"))
        #expect(
            startParams["developerInstructions"]?.stringValue
                == RelayControllerInstructions.developer
        )
        #expect(
            startParams["dynamicTools"]?.arrayValue?.count
                == RelayDynamicTools.definitions.count
        )
    }

    @Test
    func usesConfiguredInternalThreadName() async throws {
        let rpc = ControllerRPCStub()
        let store = ControllerThreadStoreStub()
        let session = CodexControllerSessionAdapter(
            rpc: rpc,
            store: store,
            cwd: "/Users/test/Work",
            threadName: "Relay Attention Classifier"
        )

        _ = try await session.ensureControllerThread(configuration: .default)

        let params = try #require(
            await rpc.params(for: "thread/name/set")?.objectValue
        )
        #expect(params["name"] == .string("Relay Attention Classifier"))
    }

    @Test
    func routesDynamicToolCallsAndPublishesTheCompletedAnswer() async throws {
        let rpc = ControllerRPCStub()
        let store = ControllerThreadStoreStub()
        let session = CodexControllerSessionAdapter(
            rpc: rpc,
            store: store,
            cwd: "/Users/test/Work"
        )
        let controller = try await session.ensureControllerThread(
            configuration: .default
        )
        let stream = try await session.submitUserText(
            "What is the status?",
            to: controller
        )
        var iterator = stream.makeAsyncIterator()
        let turnParams = try #require(
            await rpc.params(for: "turn/start")?.objectValue
        )
        #expect(turnParams["model"] == .string("gpt-5.6-luna"))
        #expect(turnParams["effort"] == .string("medium"))

        await rpc.emit(
            .serverRequest(
                CodexServerRequest(
                    id: .string("rpc-call-1"),
                    method: "item/tool/call",
                    params: .object([
                        "threadId": .string("controller-1"),
                        "turnId": .string("turn-1"),
                        "callId": .string("tool-call-1"),
                        "tool": .string("relay_get_recent_tasks"),
                        "arguments": .object([:]),
                    ])
                )
            )
        )
        let toolEvent = try #require(try await iterator.next())
        guard case let .dynamicToolCall(call) = toolEvent else {
            Issue.record("Expected a dynamic tool call")
            return
        }
        #expect(call.id == "tool-call-1")
        #expect(call.toolName == "relay_get_recent_tasks")

        try await session.completeToolCall(
            call,
            with: RelayToolCallResult(
                success: true,
                text: #"{"ok":true,"tasks":[]}"#
            )
        )

        let response = try #require(
            await rpc.response(for: .string("rpc-call-1"))?.objectValue
        )
        #expect(response["success"] == .bool(true))
        #expect(
            response["contentItems"]?.arrayValue?.first?["text"]?.stringValue
                == #"{"ok":true,"tasks":[]}"#
        )

        await rpc.emit(agentMessageStarted(
            id: "message-1",
            phase: "final_answer"
        ))
        await rpc.emit(agentMessageDelta(
            id: "message-1",
            text: "Two tasks are active."
        ))
        let deltaEvent = try #require(try await iterator.next())
        #expect(deltaEvent == .textDelta("Two tasks are active."))
        await rpc.emit(
            .notification(
                method: "turn/completed",
                params: .object([
                    "threadId": .string("controller-1"),
                    "turn": .object([
                        "id": .string("turn-1"),
                        "status": .string("completed"),
                        "items": .array([
                            .object([
                                "id": .string("message-1"),
                                "type": .string("agentMessage"),
                                "phase": .string("final_answer"),
                                "text": .string("Two tasks are active."),
                            ]),
                        ]),
                    ]),
                ])
            )
        )

        let finalEvent = try #require(try await iterator.next())
        #expect(finalEvent == .finalText("Two tasks are active."))
        #expect(try await iterator.next() == nil)
    }

    @Test
    func streamsOnlyFinalAnswerMessagesIntoRelayChat() async throws {
        let rpc = ControllerRPCStub()
        let session = CodexControllerSessionAdapter(
            rpc: rpc,
            store: ControllerThreadStoreStub(),
            cwd: "/Users/test/Work"
        )
        let controller = try await session.ensureControllerThread(
            configuration: .default
        )
        let stream = try await session.submitUserText(
            "Hello",
            to: controller
        )
        var iterator = stream.makeAsyncIterator()

        await rpc.emit(agentMessageStarted(
            id: "commentary-message",
            phase: "commentary"
        ))
        await rpc.emit(agentMessageDelta(
            id: "commentary-message",
            text: "I am checking the operating guidance."
        ))
        await rpc.emit(agentMessageStarted(
            id: "final-message",
            phase: "final_answer"
        ))
        await rpc.emit(agentMessageDelta(
            id: "final-message",
            text: "Hey — I’m Relay."
        ))

        #expect(
            try await iterator.next()
                == .textDelta("Hey — I’m Relay.")
        )

        await rpc.emit(.notification(
            method: "turn/completed",
            params: .object([
                "threadId": .string("controller-1"),
                "turn": .object([
                    "id": .string("turn-1"),
                    "status": .string("completed"),
                    "items": .array([
                        .object([
                            "id": .string("commentary-message"),
                            "type": .string("agentMessage"),
                            "phase": .string("commentary"),
                            "text": .string(
                                "I am checking the operating guidance."
                            ),
                        ]),
                        .object([
                            "id": .string("final-message"),
                            "type": .string("agentMessage"),
                            "phase": .string("final_answer"),
                            "text": .string("Hey — I’m Relay."),
                        ]),
                    ]),
                ]),
            ])
        ))

        #expect(
            try await iterator.next()
                == .finalText("Hey — I’m Relay.")
        )
        #expect(try await iterator.next() == nil)
    }

    @Test
    func resumesTheStoredToolEnabledControllerThread() async throws {
        let rpc = ControllerRPCStub(
            storedThread: .object([
                "id": .string("old-controller"),
            ])
        )
        let store = ControllerThreadStoreStub(id: "old-controller")
        let session = CodexControllerSessionAdapter(
            rpc: rpc,
            store: store,
            cwd: "/Users/test/Work"
        )

        let controller = try await session.ensureControllerThread(
            configuration: .default
        )

        #expect(controller.id == "old-controller")
        #expect(await store.loadThreadID() == "old-controller")
        let methods = await rpc.recordedMethods()
        #expect(methods.contains("thread/resume"))
        #expect(!methods.contains("thread/start"))

        let resumeParams = try #require(
            await rpc.params(for: "thread/resume")?.objectValue
        )
        #expect(resumeParams["approvalPolicy"] == .string("never"))
        #expect(resumeParams["sandbox"] == .string("read-only"))
        #expect(resumeParams["excludeTurns"] == .bool(true))
        #expect(resumeParams["cwd"] == .string("/Users/test/Work"))
        #expect(resumeParams["model"] == .string("gpt-5.6-luna"))
        #expect(
            resumeParams["developerInstructions"]?.stringValue
                == RelayControllerInstructions.developer
        )
    }

    @Test
    func declinesControllerRequestInterleavedBeforeResumeReturns()
        async throws
    {
        let rpc = ControllerRPCStub(
            storedThread: .object(["id": .string("old-controller")]),
            suspendsResume: true
        )
        let identity = RelayControllerIdentity(
            store: ControllerThreadStoreStub(id: "old-controller")
        )
        let session = CodexControllerSessionAdapter(
            rpc: rpc,
            identity: identity,
            cwd: "/Users/test/Work"
        )

        let controllerTask = Task {
            try await session.ensureControllerThread(
                configuration: .default
            )
        }
        await rpc.waitForRequest(method: "thread/resume")
        await rpc.emit(.serverRequest(CodexServerRequest(
            id: .string("interleaved-controller-approval"),
            method: "item/commandExecution/requestApproval",
            params: .object([
                "threadId": .string("old-controller"),
                "turnId": .string("turn"),
            ])
        )))

        let response = await rpc.waitForResponse(
            to: .string("interleaved-controller-approval")
        )
        await rpc.resolveResume()
        _ = try await controllerTask.value

        #expect(response?["decision"] == .string("decline"))
    }

    @Test
    func declinesOnlyHiddenControllerRequestsAndLeavesWorkerRequestsForTheUser()
        async throws
    {
        let rpc = ControllerRPCStub()
        let session = CodexControllerSessionAdapter(
            rpc: rpc,
            store: ControllerThreadStoreStub(),
            cwd: "/Users/test/Work"
        )
        _ = try await session.ensureControllerThread(
            configuration: .default
        )

        await rpc.emit(
            .serverRequest(
                CodexServerRequest(
                    id: .string("worker-approval"),
                    method: "item/commandExecution/requestApproval",
                    params: .object([
                        "threadId": .string("worker-1"),
                        "turnId": .string("worker-turn-1"),
                    ])
                )
            )
        )
        await rpc.emit(
            .serverRequest(
                CodexServerRequest(
                    id: .string("worker-input"),
                    method: "item/tool/requestUserInput",
                    params: .object([
                        "threadId": .string("worker-1"),
                        "turnId": .string("worker-turn-1"),
                    ])
                )
            )
        )
        await rpc.emit(
            .serverRequest(
                CodexServerRequest(
                    id: .string("worker-legacy-approval"),
                    method: "execCommandApproval",
                    params: .object([
                        "conversationId": .string("worker-1"),
                    ])
                )
            )
        )
        await rpc.emit(
            .serverRequest(
                CodexServerRequest(
                    id: .string("controller-approval"),
                    method: "item/commandExecution/requestApproval",
                    params: .object([
                        "threadId": .string("controller-1"),
                        "turnId": .string("controller-turn-1"),
                    ])
                )
            )
        )
        await rpc.emit(
            .serverRequest(
                CodexServerRequest(
                    id: .string("controller-input"),
                    method: "item/tool/requestUserInput",
                    params: .object([
                        "threadId": .string("controller-1"),
                        "turnId": .string("controller-turn-1"),
                    ])
                )
            )
        )
        await rpc.emit(
            .serverRequest(
                CodexServerRequest(
                    id: .string("controller-legacy-approval"),
                    method: "execCommandApproval",
                    params: .object([
                        "conversationId": .string("controller-1"),
                    ])
                )
            )
        )

        let approval = try #require(await rpc.waitForResponse(
            to: .string("controller-approval")
        )?.objectValue)
        #expect(approval["decision"] == .string("decline"))

        let input = try #require(await rpc.waitForResponse(
            to: .string("controller-input")
        )?.objectValue)
        #expect(input["answers"] == .object([:]))
        let legacy = try #require(await rpc.waitForResponse(
            to: .string("controller-legacy-approval")
        )?.objectValue)
        #expect(legacy["decision"] == .string("denied"))
        #expect(await rpc.response(for: .string("worker-approval")) == nil)
        #expect(await rpc.response(for: .string("worker-input")) == nil)
        #expect(
            await rpc.response(for: .string("worker-legacy-approval")) == nil
        )
    }

    @Test
    func liveIdentityPreventsControllerOwnershipWhenPersistenceFails()
        async throws
    {
        let store = NonPersistingControllerThreadStore()
        let identity = RelayControllerIdentity(store: store)
        let adapterRPC = ControllerRPCStub()
        let brokerRPC = ControllerRPCStub()
        let session = CodexControllerSessionAdapter(
            rpc: adapterRPC,
            identity: identity,
            cwd: "/Users/test/Work"
        )
        let broker = RelayPendingInteractionBroker(
            rpc: brokerRPC,
            controllerIdentity: identity
        )

        let controller = try await session.ensureControllerThread(
            configuration: .default
        )
        #expect(controller.id == "controller-1")
        #expect(await store.loadThreadID() == nil)
        #expect(await identity.currentThreadID() == "controller-1")

        try await broker.start()
        let controllerRequest = CodexServerRequest(
            id: .string("controller-owned"),
            method: "item/commandExecution/requestApproval",
            params: .object([
                "threadId": .string("controller-1"),
                "turnId": .string("turn"),
                "itemId": .string("controller-item"),
            ])
        )
        await adapterRPC.emit(.serverRequest(controllerRequest))
        await brokerRPC.emit(.serverRequest(controllerRequest))
        await brokerRPC.emit(
            .serverRequest(
                CodexServerRequest(
                    id: .string("worker-owned"),
                    method: "item/tool/requestUserInput",
                    params: .object([
                        "threadId": .string("worker"),
                        "turnId": .string("turn"),
                        "itemId": .string("worker-item"),
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

        let response = try #require(await adapterRPC.waitForResponse(
            to: .string("controller-owned")
        )?.objectValue)
        #expect(response["decision"] == .string("decline"))
        for _ in 0..<200
        where await broker.interaction(threadID: "worker") == nil {
            await Task.yield()
        }
        #expect(await broker.interaction(threadID: "worker") != nil)
        #expect(await broker.interaction(threadID: "controller-1") == nil)
    }
}

private func agentMessageStarted(
    id: String,
    phase: String
) -> CodexServerEvent {
    .notification(
        method: "item/started",
        params: .object([
            "threadId": .string("controller-1"),
            "turnId": .string("turn-1"),
            "item": .object([
                "id": .string(id),
                "type": .string("agentMessage"),
                "phase": .string(phase),
                "text": .string(""),
            ]),
        ])
    )
}

private func agentMessageDelta(
    id: String,
    text: String
) -> CodexServerEvent {
    .notification(
        method: "item/agentMessage/delta",
        params: .object([
            "threadId": .string("controller-1"),
            "turnId": .string("turn-1"),
            "itemId": .string(id),
            "delta": .string(text),
        ])
    )
}

private actor ControllerThreadStoreStub: RelayControllerThreadStoring {
    private var id: String?

    init(id: String? = nil) {
        self.id = id
    }

    func loadThreadID() -> String? {
        id
    }

    func saveThreadID(_ id: String) {
        self.id = id
    }
}

private actor NonPersistingControllerThreadStore:
    RelayControllerThreadStoring
{
    func loadThreadID() -> String? { nil }
    func saveThreadID(_ id: String) {}
}

private actor ControllerRPCStub: CodexSessionRPC {
    nonisolated let events: AsyncStream<CodexServerEvent>

    private let continuation: AsyncStream<CodexServerEvent>.Continuation
    private var requests: [(String, JSONValue)] = []
    private var responses: [JSONRPCRequestID: JSONValue] = [:]
    private let storedThread: JSONValue?
    private let suspendsResume: Bool
    private var resumeContinuations: [CheckedContinuation<Void, Never>] = []

    init(
        storedThread: JSONValue? = nil,
        suspendsResume: Bool = false
    ) {
        let pair = AsyncStream<CodexServerEvent>.makeStream(
            bufferingPolicy: .unbounded
        )
        events = pair.stream
        continuation = pair.continuation
        self.storedThread = storedThread
        self.suspendsResume = suspendsResume
    }

    func start() async throws {}

    func stop() async {
        continuation.finish()
    }

    func requestJSON(
        method: String,
        params: JSONValue,
        timeout: Duration
    ) async throws -> JSONValue {
        requests.append((method, params))
        switch method {
        case "thread/start":
            return .object([
                "thread": .object(["id": .string("controller-1")]),
            ])
        case "thread/read":
            return .object([
                "thread": storedThread
                    ?? .object(["id": .string("controller-1")]),
            ])
        case "thread/resume":
            if suspendsResume {
                await withCheckedContinuation { continuation in
                    resumeContinuations.append(continuation)
                }
            }
            let id = params["threadId"]?.stringValue
                ?? "controller-1"
            return .object([
                "thread": storedThread
                    ?? .object(["id": .string(id)]),
            ])
        case "turn/start":
            return .object([
                "turn": .object(["id": .string("turn-1")]),
            ])
        default:
            return .object([:])
        }
    }

    func respond(
        to requestID: JSONRPCRequestID,
        result: JSONValue
    ) async throws {
        responses[requestID] = result
    }

    func emit(_ event: CodexServerEvent) {
        continuation.yield(event)
    }

    func params(for method: String) -> JSONValue? {
        requests.last { $0.0 == method }?.1
    }

    func response(for id: JSONRPCRequestID) -> JSONValue? {
        responses[id]
    }

    func waitForResponse(
        to id: JSONRPCRequestID
    ) async -> JSONValue? {
        let deadline = ContinuousClock.now + .seconds(1)
        while responses[id] == nil, ContinuousClock.now < deadline {
            try? await Task.sleep(for: .milliseconds(10))
        }
        return responses[id]
    }

    func recordedMethods() -> [String] {
        requests.map(\.0)
    }

    func waitForRequest(method: String) async {
        let deadline = ContinuousClock.now + .seconds(1)
        while !requests.contains(where: { $0.0 == method }),
              ContinuousClock.now < deadline {
            try? await Task.sleep(for: .milliseconds(10))
        }
    }

    func resolveResume() {
        guard !resumeContinuations.isEmpty else { return }
        resumeContinuations.removeFirst().resume()
    }
}
