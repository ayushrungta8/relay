import Foundation
import RelayBrain
import RelayCodexBridge
import RelayCore
import Testing

struct RelayControllerSupervisionAdapterTests {
    @Test
    func attentionInboxIncludesExactPendingQuestionsAndApprovals() async {
        let base = ControllerSupervisionStub(
            attention: [makeTask(id: "worker")]
        )
        let adapter = RelayControllerSupervisionAdapter(
            base: base,
            pendingInteractions: {
                [
                    RelayPendingInteraction(
                        id: "question",
                        threadID: "worker",
                        turnID: "turn-1",
                        kind: .questions([
                            RelayPendingQuestion(
                                id: "region",
                                header: "Region",
                                question: "Which region should we deploy to?"
                            ),
                        ])
                    ),
                    RelayPendingInteraction(
                        id: "approval",
                        threadID: "worker",
                        turnID: "turn-1",
                        kind: .approval(
                            RelayPendingApproval(
                                title: "Run deployment",
                                detail: "Deploy version 2.4 to production.",
                                canApprove: true,
                                canDecline: true
                            )
                        )
                    ),
                ]
            }
        )

        let tasks = await adapter.attentionInbox()

        #expect(
            tasks.first?.pendingRequests
                == [
                    RelayPendingRequestSummary(
                        kind: "question",
                        prompt: "Which region should we deploy to?"
                    ),
                    RelayPendingRequestSummary(
                        kind: "approval",
                        prompt: "Run deployment — Deploy version 2.4 to production."
                    ),
                ]
        )
    }
}

private struct ControllerSupervisionStub: RelaySupervisionStateReading {
    let attention: [RelayTaskSummary]

    func visibleTasks() async -> [RelayTaskSummary]? { attention }
    func attentionInbox() async -> [RelayTaskSummary] { attention }
    func currentUsage() async -> RelayControllerUsage? { nil }
    func taskReferenceContext() async -> RelayTaskReferenceContext { .init() }
}

private func makeTask(id: String) -> RelayTaskSummary {
    RelayTaskSummary(
        id: id,
        title: "Task \(id)",
        project: "/Work/Relay",
        status: "needsInput",
        updatedAt: Date()
    )
}
