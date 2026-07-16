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

        #expect(model.pendingInteraction(threadID: "worker")?.id == "worker:item:pending")
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
        #expect(
            presentation.explanation
                == "This request belongs to another Codex client. Open the task in Codex to respond."
        )
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
