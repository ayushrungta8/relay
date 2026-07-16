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
    private var runtime: RelayAppRuntime?
    private var voiceAwaitingAnswer = false

    private var loadedThreads: [CodexThread] = []
    private(set) var state: State = .idle
    private(set) var errorMessage: String?
    var commandText = ""
    private(set) var composerPhase: RelayComposerPhase = .idle
    private(set) var latestResponse: String?

    var activityStore: RelayActivityStore? {
        runtime?.activityStore
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
        commandHandler: (any RelayCommandHandling)? = nil
    ) {
        self.providerFactory = providerFactory
        self.commandHandler = commandHandler
    }

    func start() async {
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
        commandHandler = runtime.commandHandler
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
            latestResponse = try await commandHandler.submit(command)
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
        case let .failed(message):
            voiceAwaitingAnswer = false
            composerPhase = .failed(message)
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
}
