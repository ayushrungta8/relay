import Foundation
import RelayCodexClient
import RelayCore
import RelayVoice
import Testing
@testable import RelayApp

@MainActor
struct RelayFinalFixContractsTests {
    @Test
    func offlinePresentationReportsSnapshotAgeAndOffersRetry() {
        let now = Date(timeIntervalSince1970: 1_000)
        let presentation = RelayConnectionPresentation(
            state: .offline(
                message: "Disconnected",
                reconnectAttempt: 2,
                lastUpdatedAt: now.addingTimeInterval(-125)
            ),
            now: now
        )

        #expect(presentation.label == "Reconnecting · snapshot updated 2 min ago")
        #expect(presentation.detail == "Disconnected")
        #expect(presentation.showsRetry)
    }

    @Test
    func dirtyDraftStoreBlocksDismissalUntilExplicitDiscard() {
        let store = RelayPanelDraftStore()
        store.setPendingAnswer(
            "Keep this answer",
            questionID: "choice",
            interactionID: "interaction"
        )

        #expect(store.hasDirtyDraft)
        #expect(!store.canDismiss)

        store.discardPendingAnswers(interactionID: "interaction")

        #expect(!store.hasDirtyDraft)
        #expect(store.canDismiss)
    }

    @Test
    func followUpDraftPersistsUntilExplicitDiscard() {
        let store = RelayPanelDraftStore()
        store.beginFollowUp(threadID: "worker")
        store.setFollowUp("Continue with tests", threadID: "worker")

        #expect(store.followUp(threadID: "worker").isComposing)
        #expect(store.hasDirtyDraft)

        store.discardFollowUp(threadID: "worker")

        #expect(!store.followUp(threadID: "worker").isComposing)
        #expect(!store.hasDirtyDraft)
    }

    @Test
    func optionSelectionAndAnswerLabelsExposeQuestionContext() {
        let question = RelayPendingQuestion(
            id: "environment",
            header: "Environment",
            question: "Where should this run?",
            options: [.init(label: "Staging", description: "Safe preview")]
        )
        var draft = RelayPendingAnswerDraft(interactionID: "interaction")
        draft.setAnswer("Staging", for: question.id)
        let entry = RelayPendingInteractionPresentation.options(for: question)[0]

        #expect(
            RelayPendingInteractionPresentation.isSelected(
                entry,
                for: question,
                draft: draft
            )
        )
        #expect(
            RelayPendingInteractionPresentation.answerAccessibilityLabel(
                for: question
            ) == "Environment, answer"
        )
    }

    @Test
    func panelStateRefusesCollapseWhileDraftIsDirty() {
        let state = RelayNotchPanelState()
        state.presentation = .expanded
        state.drafts.setPendingAnswer(
            "Pending",
            questionID: "choice",
            interactionID: "interaction"
        )
        var requests: [RelayPanelPresentation] = []
        state.presentationRequestHandler = { requests.append($0) }

        state.requestCollapse()
        #expect(requests.isEmpty)

        state.drafts.discardPendingAnswers(interactionID: "interaction")
        state.requestCollapse()
        #expect(requests == [.compact])
    }

    @Test
    func panelToggleRefusesToDismissUntilDirtyDraftIsCancelled() {
        let state = RelayNotchPanelState()
        state.presentation = .expanded
        state.drafts.setPendingAnswer(
            "Pending",
            questionID: "choice",
            interactionID: "interaction"
        )

        #expect(state.toggleTarget() == nil)

        state.drafts.discardPendingAnswers(interactionID: "interaction")

        #expect(state.toggleTarget() == .hidden)
    }

    @Test
    func disappearingDraftOwnersRemainExplicitlyCancellable() throws {
        let store = RelayPanelDraftStore()
        store.setPendingAnswer(
            "Keep this answer",
            questionID: "choice",
            interactionID: "gone-interaction"
        )
        store.beginFollowUp(threadID: "gone-thread")
        store.setFollowUp("Keep this follow-up", threadID: "gone-thread")

        store.reconcile(
            liveThreadIDs: [],
            liveInteractionIDs: []
        )

        #expect(
            Set(store.orphanedDrafts.map(\.ownerID))
                == ["gone-interaction", "gone-thread"]
        )
        #expect(!store.canDismiss)

        for orphan in store.orphanedDrafts {
            store.discard(orphan)
        }

        #expect(store.orphanedDrafts.isEmpty)
        #expect(store.canDismiss)
    }

    @Test
    func automaticPeekCandidateUsesOnlyPriorityAttention() {
        let failed = RelayTaskActivity(
            thread: CodexThread(
                id: "failed",
                preview: "Failed",
                cwd: "/tmp",
                updatedAt: 20,
                status: .systemError
            )
        )
        let running = RelayTaskActivity(
            thread: CodexThread(
                id: "running",
                preview: "Running",
                cwd: "/tmp",
                updatedAt: 30,
                status: .active
            )
        )
        let presentation = RelayActivityPresentation(tasks: [running, failed])

        #expect(presentation.automaticPeekTrigger?.threadID == "failed")
        #expect(presentation.automaticPeekTrigger?.state == .failed)
    }

    @Test
    func panelShortcutDoesNotConflictWithOptionSpacePushToTalk() {
        #expect(RelayGlobalShortcut.panelToggle != .optionSpace)
        #expect(RelayGlobalShortcut.panelToggle.modifiers == [.command, .shift])
    }

    @Test
    func automaticPeekDismissesAfterFourSeconds() async {
        let sleeper = PeekSleeper()
        var presentations: [RelayPanelPresentation] = []
        let coordinator = RelayPanelPresentationCoordinator(
            sleep: { duration in try await sleeper.sleep(duration) },
            presentPeek: { presentations.append(.peek) },
            dismissPeek: { presentations.append(.hidden) }
        )
        let trigger = RelayAutomaticPeekTrigger(
            threadID: "worker",
            state: .needsInput,
            updatedAt: 1,
            hasUnreadCompletion: false
        )

        coordinator.observe(trigger)
        await sleeper.waitUntilSleeping()
        #expect(await sleeper.requestedDuration() == .seconds(4))
        #expect(presentations == [.peek])

        await sleeper.resume()
        for _ in 0..<100 where presentations != [.peek, .hidden] {
            await Task.yield()
        }
        #expect(presentations == [.peek, .hidden])
    }

    @Test
    func identicalAttentionTriggerPeeksAgainAfterClearedInterval() {
        var peekCount = 0
        let coordinator = RelayPanelPresentationCoordinator(
            sleep: { _ in throw CancellationError() },
            presentPeek: { peekCount += 1 },
            dismissPeek: {}
        )
        let trigger = RelayAutomaticPeekTrigger(
            threadID: "worker",
            state: .needsInput,
            updatedAt: 1,
            hasUnreadCompletion: false
        )

        coordinator.observe(trigger)
        coordinator.observe(nil)
        coordinator.observe(trigger)

        #expect(peekCount == 2)
    }
}

private actor PeekSleeper {
    private var duration: Duration?
    private var continuation: CheckedContinuation<Void, any Error>?

    func sleep(_ duration: Duration) async throws {
        self.duration = duration
        try await withCheckedThrowingContinuation { continuation = $0 }
    }

    func waitUntilSleeping() async {
        while duration == nil { await Task.yield() }
    }

    func requestedDuration() -> Duration? { duration }

    func resume() {
        continuation?.resume()
        continuation = nil
    }
}
