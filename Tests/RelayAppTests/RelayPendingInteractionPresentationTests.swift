import Foundation
import RelayBrain
import RelayCodexBridge
import RelayCodexClient
import RelayCore
import Testing
@testable import RelayApp

struct RelayPendingInteractionPresentationTests {
    @MainActor
    @Test
    func appModelPublishesRequestsObservedByItsBroker() async throws {
        let rpc = PresentationPendingRPCStub()
        let broker = RelayPendingInteractionBroker(rpc: rpc)
        let model = RelayAppModel(
            commandHandler: PresentationCommandHandlerStub(),
            pendingInteractionBroker: broker
        )

        await model.start()
        await rpc.emit(
            .serverRequest(
                CodexServerRequest(
                    id: .string("pending"),
                    method: "item/tool/requestUserInput",
                    params: .object([
                        "threadId": .string("worker"),
                        "turnId": .string("turn"),
                        "itemId": .string("item"),
                        "questions": .array([
                            .object([
                                "id": .string("choice"),
                                "header": .string("Choice"),
                                "question": .string("Which option?"),
                            ]),
                        ]),
                    ])
                )
            )
        )
        for _ in 0..<100 where model.pendingInteraction(threadID: "worker") == nil {
            await Task.yield()
        }

        #expect(model.pendingInteraction(threadID: "worker") != nil)
    }

    @MainActor
    @Test
    func appModelPreservesParallelSameThreadInteractionsInArrivalOrder()
        async throws
    {
        let rpc = PresentationPendingRPCStub()
        let broker = RelayPendingInteractionBroker(rpc: rpc)
        let model = RelayAppModel(
            commandHandler: PresentationCommandHandlerStub(),
            pendingInteractionBroker: broker
        )
        await model.start()

        await rpc.emit(.serverRequest(pendingRequest(
            requestID: "z-first",
            itemID: "first"
        )))
        await rpc.emit(.serverRequest(pendingRequest(
            requestID: "a-second",
            itemID: "second"
        )))
        for _ in 0..<200
        where model.pendingInteractions(threadID: "worker").count < 2 {
            await Task.yield()
        }

        let interactions = model.pendingInteractions(threadID: "worker")
        #expect(interactions.count == 2)
        #expect(Set(interactions.map(\.id)).count == 2)
        #expect(interactions.compactMap { interaction in
            guard case let .questions(questions) = interaction.kind else {
                return nil
            }
            return questions.first?.id
        } == ["first", "second"])
    }

    @MainActor
    @Test
    func ownedQuestionsCanBeAnsweredInRelay() {
        let interaction = RelayPendingInteraction(
            id: "owned-question",
            threadID: "worker-1",
            turnID: "turn-1",
            kind: .questions([
                RelayPendingQuestion(
                    id: "choice",
                    header: "Choice",
                    question: "Which option?",
                    options: [
                        RelayPendingQuestionOption(
                            label: "A",
                            description: "Choose A."
                        ),
                    ]
                ),
            ])
        )

        let presentation = RelayPendingInteractionPresentation(
            task: waitingTask(id: "worker-1"),
            ownedInteraction: interaction
        )

        #expect(presentation.isRelayOwned)
        #expect(presentation.action == .answerQuestions)
        #expect(presentation.interaction == interaction)
        #expect(presentation.allowsTaskManagement)
    }

    @MainActor
    @Test
    func waitingTaskWithoutAnOwnedRequestOnlyOffersOpenInCodex() {
        let presentation = RelayPendingInteractionPresentation(
            task: waitingTask(id: "external-worker"),
            ownedInteraction: nil
        )

        #expect(!presentation.isRelayOwned)
        #expect(presentation.action == .openInCodex)
        #expect(presentation.interaction == nil)
        #expect(!presentation.allowsTaskManagement)
        #expect(
            presentation.explanation
                == "This request belongs to another Codex client. Open the task in Codex to respond."
        )
    }

    @MainActor
    @Test
    func ownedToExternalTransitionClearsOpenFollowUpComposer() {
        let task = waitingTask(id: "transition-worker")
        let owned = RelayPendingInteractionPresentation(
            task: task,
            ownedInteraction: RelayPendingInteraction(
                id: "owned",
                threadID: task.id,
                turnID: "turn",
                kind: .approval(.init(
                    title: "Approve?",
                    canApprove: true,
                    canDecline: true
                ))
            )
        )
        let external = RelayPendingInteractionPresentation(
            task: task,
            ownedInteraction: nil
        )
        var followUp = RelayTaskCardFollowUpState()
        followUp.beginFollowUp(
            allowsTaskManagement: owned.allowsTaskManagement
        )
        followUp.draft = "private follow-up"

        followUp.synchronize(
            allowsTaskManagement: external.allowsTaskManagement
        )

        #expect(external.action == .openInCodex)
        #expect(!external.allowsTaskManagement)
        #expect(!followUp.isComposing)
        #expect(followUp.draft.isEmpty)
    }

    @MainActor
    @Test
    func ownedApprovalUsesRelayDecisionControls() {
        let interaction = RelayPendingInteraction(
            id: "owned-approval",
            threadID: "worker-2",
            turnID: "turn-2",
            kind: .approval(
                RelayPendingApproval(
                    title: "Approve command?",
                    detail: "Run swift test",
                    canApprove: true,
                    canDecline: true
                )
            )
        )

        let presentation = RelayPendingInteractionPresentation(
            task: waitingTask(id: "worker-2"),
            ownedInteraction: interaction
        )

        #expect(presentation.action == .reviewApproval)
        #expect(presentation.isRelayOwned)
    }

    @MainActor
    @Test
    func changedInteractionIdentityClearsReusedSecretAnswers() {
        let question = RelayPendingQuestion(
            id: "credential",
            header: "Credential",
            question: "Enter the credential",
            isSecret: true
        )
        var draft = RelayPendingAnswerDraft(interactionID: "old")
        draft.setAnswer("secret-value", for: question.id)
        #expect(draft.canSubmit(questions: [question]))

        draft.synchronize(interactionID: "new")

        #expect(draft.answer(for: question.id).isEmpty)
        #expect(!draft.canSubmit(questions: [question]))
    }

    @MainActor
    @Test
    func sameProtocolRequestReplacementClearsDraftWithoutEmptyObservation()
        async throws
    {
        let rpc = PresentationPendingRPCStub()
        let broker = RelayPendingInteractionBroker(rpc: rpc)
        try await broker.start()
        let request = pendingRequest(
            requestID: "same-request",
            itemID: "same-item"
        )
        await rpc.emit(.serverRequest(request))
        for _ in 0..<200
        where await broker.interaction(threadID: "worker") == nil {
            await Task.yield()
        }
        let old = try #require(
            await broker.interaction(threadID: "worker")
        )
        guard case let .questions(questions) = old.kind else {
            Issue.record("Expected questions")
            return
        }
        var draft = RelayPendingAnswerDraft(interactionID: old.id)
        draft.setAnswer("secret", for: questions[0].id)
        #expect(draft.canSubmit(questions: questions))

        await rpc.emit(.lifecycle(.failed("Disconnected")))
        await rpc.emit(.serverRequest(request))
        for _ in 0..<200
        where await broker.interaction(threadID: "worker")?.id == old.id {
            await Task.yield()
        }
        let replacement = try #require(
            await broker.interaction(threadID: "worker")
        )

        #expect(replacement.id != old.id)
        draft.synchronize(interactionID: replacement.id)
        #expect(draft.answer(for: questions[0].id).isEmpty)
        #expect(!draft.canSubmit(questions: questions))
    }

    @MainActor
    @Test
    func duplicateOptionLabelsHaveDistinctStableIdentities() {
        let question = RelayPendingQuestion(
            id: "environment",
            header: "Environment",
            question: "Which environment?",
            options: [
                .init(label: "Default", description: "First source"),
                .init(label: "Default", description: "Second source"),
            ]
        )

        let options = RelayPendingInteractionPresentation.options(
            for: question
        )

        #expect(options.map(\.id).count == 2)
        #expect(Set(options.map(\.id)).count == 2)
        #expect(options.map(\.option.label) == ["Default", "Default"])
    }
}

private actor PresentationPendingRPCStub: CodexSessionRPC {
    nonisolated let events: AsyncStream<CodexServerEvent>
    private let continuation: AsyncStream<CodexServerEvent>.Continuation

    init() {
        let pair = AsyncStream<CodexServerEvent>.makeStream()
        events = pair.stream
        continuation = pair.continuation
    }

    func start() async throws {}
    func stop() async { continuation.finish() }
    func requestJSON(method: String, params: JSONValue, timeout: Duration) async throws -> JSONValue { .object([:]) }
    func respond(to requestID: JSONRPCRequestID, result: JSONValue) async throws {}
    func emit(_ event: CodexServerEvent) { continuation.yield(event) }
}

private actor PresentationCommandHandlerStub: RelayCommandHandling {
    func submit(_ text: String) async throws -> String { "OK" }
}

private func waitingTask(id: String) -> RelayTaskActivity {
    RelayTaskActivity(
        thread: CodexThread(
            id: id,
            name: "Waiting task",
            preview: "Waiting task",
            cwd: "/Projects/Relay",
            updatedAt: 1_784_210_400,
            status: .active,
            activeFlags: [.waitingOnUserInput]
        )
    )
}

private func pendingRequest(
    requestID: String,
    itemID: String
) -> CodexServerRequest {
    CodexServerRequest(
        id: .string(requestID),
        method: "item/tool/requestUserInput",
        params: .object([
            "threadId": .string("worker"),
            "turnId": .string("turn"),
            "itemId": .string(itemID),
            "questions": .array([
                .object([
                    "id": .string(itemID),
                    "header": .string("Choice"),
                    "question": .string("Which option?"),
                    "isSecret": .bool(true),
                ]),
            ]),
        ])
    )
}
