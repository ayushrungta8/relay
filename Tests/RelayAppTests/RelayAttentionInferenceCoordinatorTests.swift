import Foundation
import RelayCore
import Testing
@testable import RelayApp

struct RelayAttentionInferenceCoordinatorTests {
    @Test
    func localPositiveNeedsNoAI() async {
        let ai = CountingAttentionClassifier(needsReply: false)
        let coordinator = RelayAttentionInferenceCoordinator(
            aiClassifier: ai,
            dismissalStore: .inMemory()
        )

        let preparation = await coordinator.prepare(
            tasks: [task(text: "Please review and reply approved.")]
        )

        #expect(preparation.candidates.isEmpty)
        #expect(
            preparation.tasks.first?.attentionReason
                == .inferredReplyRequest
        )
        #expect(await ai.calls == 0)
    }

    @Test
    func ambiguousTurnIsClassifiedOnceAndCached() async throws {
        let ai = CountingAttentionClassifier(needsReply: true)
        let coordinator = RelayAttentionInferenceCoordinator(
            aiClassifier: ai,
            dismissalStore: .inMemory()
        )
        let ambiguous = task(text: "Would you like me to continue?")

        let first = await coordinator.prepare(tasks: [ambiguous])
        let second = await coordinator.prepare(tasks: [ambiguous])
        let candidate = try #require(first.candidates.first)
        let update = await coordinator.classify(candidate)
        let third = await coordinator.prepare(tasks: [ambiguous])

        #expect(second.candidates.isEmpty)
        #expect(update.needsReply)
        #expect(third.tasks.first?.hasInferredReplyRequest == true)
        #expect(await ai.calls == 1)
    }

    @Test
    func classifierFailureFailsClosedAndIsCached() async throws {
        let ai = CountingAttentionClassifier(error: TestFailure.failed)
        let coordinator = RelayAttentionInferenceCoordinator(
            aiClassifier: ai,
            dismissalStore: .inMemory()
        )
        let ambiguous = task(text: "Should I proceed?")
        let first = await coordinator.prepare(tasks: [ambiguous])
        let candidate = try #require(first.candidates.first)

        let update = await coordinator.classify(candidate)
        let second = await coordinator.prepare(tasks: [ambiguous])

        #expect(!update.needsReply)
        #expect(second.candidates.isEmpty)
        #expect(second.tasks.first?.attentionState == .idle)
        #expect(await ai.calls == 1)
    }

    @Test
    func dismissalPersistsAndRemainsBounded() {
        let suite = "RelayAttentionTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite) ?? .standard
        defaults.removePersistentDomain(forName: suite)
        let first = RelayAttentionDismissalStore(defaults: defaults)

        for index in 0...200 {
            first.dismiss(
                threadID: "worker",
                turnID: "turn-\(index)",
                at: Date(timeIntervalSince1970: TimeInterval(index))
            )
        }

        let restored = RelayAttentionDismissalStore(defaults: defaults)
        #expect(!restored.contains(threadID: "worker", turnID: "turn-0"))
        #expect(restored.contains(threadID: "worker", turnID: "turn-200"))
    }

    private func task(text: String) -> RelayTaskActivity {
        RelayTaskActivity(
            thread: CodexThread(
                id: "worker",
                preview: "Worker",
                cwd: "/tmp",
                updatedAt: 1,
                status: .idle
            ),
            latestTurnStatus: .completed,
            latestFinalResponse: RelayTaskFinalResponse(
                turnID: "turn-1",
                text: text,
                fingerprint: String(text.hashValue)
            )
        )
    }
}

private actor CountingAttentionClassifier: RelayAttentionAIClassifying {
    private let needsReply: Bool
    private let error: (any Error)?
    private(set) var calls = 0

    init(needsReply: Bool) {
        self.needsReply = needsReply
        error = nil
    }

    init(error: any Error) {
        needsReply = false
        self.error = error
    }

    func classify(
        _ text: String
    ) async throws -> RelayAIAttentionClassification {
        calls += 1
        if let error { throw error }
        return RelayAIAttentionClassification(
            needsReply: needsReply,
            reason: "fixture"
        )
    }
}

private enum TestFailure: Error {
    case failed
}
