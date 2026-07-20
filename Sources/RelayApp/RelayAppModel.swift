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
    private let voiceReadiness: any RelayVoiceReadinessChecking
    private let injectedStartVoice: (@MainActor () -> Void)?
    private let voiceSettingsOpener: RelayVoiceSettingsOpener
    let settings: RelaySettingsStore

    private var loadedThreads: [CodexThread] = []
    private(set) var state: State = .idle
    private(set) var errorMessage: String?
    var commandText = ""
    private(set) var composerPhase: RelayComposerPhase = .idle
    private(set) var isSpeaking = false
    private(set) var latestResponse: String?
    private(set) var chatMessages: [RelayChatMessage] = []
    private(set) var voiceSetup: RelayVoiceSetupPresentation?
    private(set) var isResolvingVoiceSetup = false
    private(set) var settingsErrorMessage: String?
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

    /// Transient voice state shown in the notch header in place of the
    /// resting summary. `.inactive` falls back to the usual "All clear".
    var voiceActivity: RelayVoiceActivity {
        switch composerPhase {
        case .listening:
            return .listening
        case .sending:
            return isSpeaking ? .speaking : .thinking
        case .idle:
            return isSpeaking ? .speaking : .inactive
        case .failed:
            return .inactive
        }
    }

    init(
        providerFactory: (@Sendable
            () -> any CodexThreadProviding)? = nil,
        commandHandler: (any RelayCommandHandling)? = nil,
        pendingInteractionBroker: RelayPendingInteractionBroker? = nil,
        activityStore: RelayActivityStore? = nil,
        settings: RelaySettingsStore = RelaySettingsStore(),
        voiceReadiness: any RelayVoiceReadinessChecking =
            RelayVoiceReadinessService(),
        startVoice: (@MainActor () -> Void)? = nil,
        voiceSettingsOpener: RelayVoiceSettingsOpener = .init()
    ) {
        self.providerFactory = providerFactory
        self.commandHandler = commandHandler
        self.pendingInteractionBroker = pendingInteractionBroker
        injectedActivityStore = activityStore
        self.voiceReadiness = voiceReadiness
        injectedStartVoice = startVoice
        self.voiceSettingsOpener = voiceSettingsOpener
        self.settings = settings
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
            settings: settings,
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
        await Self.performStartup(
            registerShortcut: { [weak self] in
                self?.retryShortcutRegistration()
            },
            startServices: { [weak self] in
                guard let self else { return }
                await self.startPendingInteractionObservation(
                    broker: runtime.pendingInteractionBroker
                )
                await runtime.activityStore.start()
            }
        )
    }

    static func performStartup(
        registerShortcut: () -> Void,
        startServices: () async -> Void
    ) async {
        registerShortcut()
        await startServices()
    }

    func retryShortcutRegistration() {
        guard let runtime, runtime.activeShortcut == nil else { return }
        do {
            try runtime.startShortcut { [weak self] event in
                self?.handleShortcut(event)
            }
            if case .failed = composerPhase {
                composerPhase = .idle
            }
        } catch {
            composerPhase = .failed(error.localizedDescription)
        }
    }

    func applySettingsChange(_ change: RelaySettingsChange) {
        guard let runtime else { return }
        do {
            try runtime.applySettingsChange(change)
            if change != .restoredDefaults {
                settingsErrorMessage = nil
            }
        } catch {
            if case .shortcut = change,
               let activeShortcut = runtime.activeShortcut {
                settings.restoreShortcutWithoutNotifying(activeShortcut)
            }
            settingsErrorMessage = error.localizedDescription
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
        appendUserMessage(command)

        do {
            let answer = try await commandHandler.submit(
                command,
                onAnswerUpdate: { [weak self] answer in
                    await self?.receiveAnswerUpdate(answer)
                }
            )
            receiveAnswerUpdate(answer)
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

    func beginVoiceAttempt() {
        guard canBeginCommand else { return }
        let readiness = voiceReadiness.currentState()
        guard readiness == .ready else {
            voiceSetup = RelayVoiceSetupPresentation(state: readiness)
            return
        }

        voiceSetup = nil
        latestResponse = nil
        voiceAwaitingAnswer = false
        if let injectedStartVoice {
            injectedStartVoice()
        } else {
            runtime?.pushToTalk.press()
        }
    }

    func performVoiceSetupPrimaryAction() async {
        guard let action = voiceSetup?.primaryAction else { return }
        switch action {
        case .requestPermissions:
            guard !isResolvingVoiceSetup else { return }
            isResolvingVoiceSetup = true
            let state = await voiceReadiness.requestRequiredPermissions()
            isResolvingVoiceSetup = false
            voiceSetup = state == .ready
                ? .ready
                : RelayVoiceSetupPresentation(state: state)
        case let .openSettings(destination):
            voiceSettingsOpener.open(destination)
        }
    }

    func dismissVoiceSetup() {
        voiceSetup = nil
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
        switch event {
        case .pressed:
            beginVoiceAttempt()
        case .released:
            guard let runtime else { return }
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
            isSpeaking = false
            composerPhase = .listening
        case .finishing:
            voiceAwaitingAnswer = true
            composerPhase = .sending
        case let .failed(failure):
            voiceAwaitingAnswer = false
            composerPhase = .idle
            voiceSetup = if let readiness = failure.readinessState {
                RelayVoiceSetupPresentation(state: readiness)
            } else {
                .runtimeFailure(message: failure.message)
            }
        }
    }

    private func handleVoiceEvent(
        _ event: RelayVoiceControllerEvent
    ) async {
        switch event {
        case let .transcript(text):
            isSpeaking = false
            commandText = text
            appendUserMessage(text)
            composerPhase = .sending
        case let .answer(answer):
            receiveAnswerUpdate(answer)
            commandText = ""
            voiceAwaitingAnswer = false
            composerPhase = .idle
            await refresh()
        case let .answerUpdate(answer):
            receiveAnswerUpdate(answer)
        case let .speaking(isSpeaking):
            self.isSpeaking = isSpeaking
        case let .failed(message):
            isSpeaking = false
            voiceAwaitingAnswer = false
            composerPhase = .idle
            voiceSetup = .runtimeFailure(message: message)
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
        if chatMessages.last?.role == .relay {
            chatMessages[chatMessages.count - 1].text = answer
        } else {
            chatMessages.append(
                RelayChatMessage(role: .relay, text: answer)
            )
        }
    }

    private func appendUserMessage(_ text: String) {
        chatMessages.append(
            RelayChatMessage(role: .user, text: text)
        )
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
