import Foundation
import Observation
import RelayCodexBridge
import RelayCodexClient
import RelayCore
import RelayVoice

@MainActor
@Observable
final class RelayAppModel {
    enum State: Equatable {
        case idle
        case loading
        case loaded
        case failed
    }

    private let providerFactory:
        (@Sendable () -> any CodexThreadProviding)?
    private var commandHandler: (any RelayCommandHandling)?
    private var pendingInteractionBroker: RelayPendingInteractionBroker?
    private var runtime: RelayAppRuntime?
    private var pendingInteractionTask: Task<Void, Never>?
    private var voiceAwaitingAnswer = false
    private let injectedActivityStore: RelayActivityStore?

    private var loadedThreads: [CodexThread] = []
    private(set) var state: State = .idle
    private(set) var errorMessage: String?
    var commandText = ""
    private(set) var composerPhase: RelayComposerPhase = .idle
    private(set) var latestResponse: String?
    private var observedPendingInteractions: [RelayPendingInteraction] = []
    private var resolvingInteractionsByID:
        [String: RetainedResolvingInteraction] = [:]

    var pendingInteractions: [RelayPendingInteraction] {
        let observedIDs = Set(observedPendingInteractions.map(\.id))
        let retained = resolvingInteractionsByID.values.filter {
            !observedIDs.contains($0.interaction.id)
                && authoritativeInputState(
                    for: $0.interaction.threadID
                ) != .cleared
        }.map(\.interaction)
        return observedPendingInteractions + retained.sorted { $0.id < $1.id }
    }

    var activityStore: RelayActivityStore? {
        runtime?.activityStore ?? injectedActivityStore
    }

    var threads: [CodexThread] {
        guard let activityStore else { return loadedThreads }
        return (
            activityStore.attentionTasks
                + activityStore.runningTasks
                + activityStore.recentTasks
        ).map(\.thread)
    }

    var isVoiceActive: Bool {
        guard let runtime else { return false }
        return switch runtime.pushToTalk.state {
        case .listening, .finishing:
            true
        case .idle, .failed:
            false
        }
    }

    init(
        providerFactory: (@Sendable
            () -> any CodexThreadProviding)? = nil,
        commandHandler: (any RelayCommandHandling)? = nil,
        pendingInteractionBroker: RelayPendingInteractionBroker? = nil,
        activityStore: RelayActivityStore? = nil
    ) {
        self.providerFactory = providerFactory
        self.commandHandler = commandHandler
        self.pendingInteractionBroker = pendingInteractionBroker
        injectedActivityStore = activityStore
        observeActivityStore(activityStore)
    }

    func start() async {
        if let pendingInteractionBroker, pendingInteractionTask == nil {
            await startPendingInteractionObservation(
                broker: pendingInteractionBroker
            )
        }
        guard runtime == nil, commandHandler == nil else { return }

        let runtime = RelayAppRuntime(
            onVoiceEvent: { [weak self] event in
                await self?.handleVoiceEvent(event)
            },
            onPushToTalkStateChange: { [weak self] state in
                self?.handlePushToTalkState(state)
            }
        )
        self.runtime = runtime
        observeActivityStore(runtime.activityStore)
        commandHandler = runtime.commandHandler
        pendingInteractionBroker = runtime.pendingInteractionBroker
        await startPendingInteractionObservation(
            broker: runtime.pendingInteractionBroker
        )
        await runtime.activityStore.start()

        do {
            try runtime.startShortcut { [weak self] event in
                self?.handleShortcut(event)
            }
        } catch {
            composerPhase = .failed(error.localizedDescription)
        }
    }

    func refresh() async {
        guard state != .loading else { return }

        state = .loading
        errorMessage = nil

        if let activityStore {
            await activityStore.refresh()
            if activityStore.connectionState.isOffline {
                state = .failed
                errorMessage = activityStore.connectionState.errorMessage
            } else {
                state = .loaded
            }
            return
        }

        guard let providerFactory else {
            state = .idle
            return
        }

        do {
            let provider = providerFactory()
            loadedThreads = try await provider.loadThreads(limit: 25)
                .filter {
                    $0.name?
                        .trimmingCharacters(
                            in: .whitespacesAndNewlines
                        )
                        .caseInsensitiveCompare("Relay Controller")
                        != .orderedSame
                }
                .sorted(by: Self.threadComesBefore)
            state = .loaded
        } catch {
            state = .failed
            errorMessage = error.localizedDescription
        }
    }

    func submitCommand() async {
        let command = commandText.trimmingCharacters(
            in: .whitespacesAndNewlines
        )
        guard !command.isEmpty, canBeginCommand else { return }

        if commandHandler == nil {
            await start()
        }
        guard let commandHandler else {
            composerPhase = .failed(
                "Relay could not start its Codex controller."
            )
            return
        }

        composerPhase = .sending
        latestResponse = nil

        do {
            latestResponse = try await commandHandler.submit(
                command,
                onAnswerUpdate: { [weak self] answer in
                    await self?.receiveAnswerUpdate(answer)
                }
            )
            commandText = ""
            composerPhase = .idle
            await refresh()
        } catch {
            composerPhase = .failed(error.localizedDescription)
        }
    }

    func cancelVoice() async {
        guard let runtime else { return }
        voiceAwaitingAnswer = false
        await runtime.pushToTalk.cancel()
        composerPhase = .idle
    }

    func pendingInteraction(
        threadID: String
    ) -> RelayPendingInteraction? {
        pendingInteractions(threadID: threadID).first
    }

    func pendingInteractions(
        threadID: String
    ) -> [RelayPendingInteraction] {
        pendingInteractions.filter { $0.threadID == threadID }
    }

    func selectTask(threadID: String) async {
        await activityStore?.select(threadID: threadID)
    }

    func submitPendingAnswers(
        interactionID: String,
        answers: [String: [String]]
    ) async throws {
        guard let pendingInteractionBroker else {
            throw PendingInteractionError.unavailable
        }
        if let interaction = pendingInteractions.first(
            where: { $0.id == interactionID }
        ) {
            await selectTask(threadID: interaction.threadID)
        }
        try await pendingInteractionBroker.submitAnswers(
            interactionID: interactionID,
            answers: answers
        )
    }

    func submitPendingDecision(
        interactionID: String,
        decision: RelayPendingApprovalDecision
    ) async throws {
        guard let pendingInteractionBroker else {
            throw PendingInteractionError.unavailable
        }
        if let interaction = pendingInteractions.first(
            where: { $0.id == interactionID }
        ) {
            await selectTask(threadID: interaction.threadID)
        }
        try await pendingInteractionBroker.submitDecision(
            interactionID: interactionID,
            decision: decision
        )
    }

    private var canBeginCommand: Bool {
        switch composerPhase {
        case .idle, .failed:
            true
        case .listening, .sending:
            false
        }
    }

    private func handleShortcut(_ event: RelayGlobalShortcutEvent) {
        guard let runtime else { return }

        switch event {
        case .pressed:
            guard canBeginCommand else { return }
            latestResponse = nil
            voiceAwaitingAnswer = false
            runtime.pushToTalk.press()
        case .released:
            guard runtime.pushToTalk.state == .listening else {
                return
            }
            voiceAwaitingAnswer = true
            Task {
                await runtime.pushToTalk.release()
            }
        }
    }

    private func handlePushToTalkState(
        _ state: PushToTalkState
    ) {
        switch state {
        case .idle:
            if !voiceAwaitingAnswer {
                composerPhase = .idle
            }
        case .listening:
            composerPhase = .listening
        case .finishing:
            voiceAwaitingAnswer = true
            composerPhase = .sending
        case let .failed(message):
            voiceAwaitingAnswer = false
            composerPhase = .failed(message)
        }
    }

    private func handleVoiceEvent(
        _ event: RelayVoiceControllerEvent
    ) async {
        switch event {
        case let .transcript(text):
            commandText = text
            composerPhase = .sending
        case let .answer(answer):
            latestResponse = answer
            commandText = ""
            voiceAwaitingAnswer = false
            composerPhase = .idle
            await refresh()
        case let .answerUpdate(answer):
            latestResponse = answer
        case let .failed(message):
            voiceAwaitingAnswer = false
            composerPhase = .failed(message)
        }
    }

    private func startPendingInteractionObservation(
        broker: RelayPendingInteractionBroker
    ) async {
        guard pendingInteractionTask == nil else { return }
        let updates = broker.updates
        pendingInteractionTask = Task { [weak self] in
            for await interactions in updates {
                guard let self, !Task.isCancelled else { return }
                receivePendingInteractions(interactions)
            }
        }
        do {
            try await broker.start()
        } catch {
            composerPhase = .failed(
                "Relay could not observe pending Codex requests: \(error.localizedDescription)"
            )
        }
    }

    private static func threadComesBefore(
        _ lhs: CodexThread,
        _ rhs: CodexThread
    ) -> Bool {
        if lhs.status == .active, rhs.status != .active {
            return true
        }
        if lhs.status != .active, rhs.status == .active {
            return false
        }
        return lhs.updatedAt > rhs.updatedAt
    }

    func receivePendingInteractions(
        _ interactions: [RelayPendingInteraction]
    ) {
        let newIDs = Set(interactions.map(\.id))
        for interaction in observedPendingInteractions
        where interaction.state == .resolving
            && !newIDs.contains(interaction.id) {
            resolvingInteractionsByID[interaction.id] =
                RetainedResolvingInteraction(interaction: interaction)
        }
        for interaction in interactions {
            resolvingInteractionsByID.removeValue(forKey: interaction.id)
        }
        observedPendingInteractions = interactions
        reconcileResolvingInteractions()
    }

    private func reconcileResolvingInteractions() {
        let clearedIDs = resolvingInteractionsByID.compactMap {
            id, retained in
            authoritativeInputState(for: retained.interaction.threadID)
                == .cleared ? id : nil
        }
        for id in clearedIDs {
            resolvingInteractionsByID.removeValue(forKey: id)
        }
    }

    private func authoritativeInputState(
        for threadID: String
    ) -> AuthoritativeInputState {
        guard let activityStore else { return .unknown }
        let tasks = activityStore.attentionTasks
            + activityStore.runningTasks
            + activityStore.recentTasks
        if let task = tasks.first(where: { $0.id == threadID }) {
            return task.attentionState == .needsInput ? .waiting : .cleared
        }
        return activityStore.lastUpdatedAt == nil ? .unknown : .cleared
    }

    private func observeActivityStore(_ store: RelayActivityStore?) {
        store?.activityPublished = { [weak self] in
            self?.reconcileResolvingInteractions()
        }
    }

    private func receiveAnswerUpdate(_ answer: String) {
        latestResponse = answer
    }

    func reportPanelShortcutFailure(_ message: String) {
        composerPhase = .failed(message)
    }
}

private extension RelayAppModel {
    struct RetainedResolvingInteraction {
        let interaction: RelayPendingInteraction
    }

    enum AuthoritativeInputState: Equatable {
        case waiting
        case cleared
        case unknown
    }
}

private extension RelayAppModel {
    enum PendingInteractionError: LocalizedError {
        case unavailable

        var errorDescription: String? {
            "Relay cannot answer this request. Open the task in Codex."
        }
    }
}
