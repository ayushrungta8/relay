import Foundation
import RelayBrain
import RelayCodexBridge
import RelayCodexClient
import RelayVoice

@MainActor
final class RelayAppRuntime {
    let commandHandler: any RelayCommandHandling
    let pushToTalk: PushToTalkCoordinator
    let activityStore: RelayActivityStore
    let pendingInteractionBroker: RelayPendingInteractionBroker

    private let settings: RelaySettingsStore
    private let shortcutCoordinator: RelayShortcutCoordinator
    private let voiceSynthesizer: AppleSpeechSynthesizer

    init(
        settings: RelaySettingsStore,
        onVoiceEvent: @escaping @Sendable
            (RelayVoiceControllerEvent) async -> Void,
        onPushToTalkStateChange: @escaping @MainActor @Sendable
            (PushToTalkState) -> Void,
        shortcutCoordinator: RelayShortcutCoordinator = .init()
    ) {
        self.settings = settings
        self.shortcutCoordinator = shortcutCoordinator
        let rpc = PersistentCodexAppServerClient()
        let controllerThreadStore = RelayControllerThreadFileStore()
        let controllerIdentity = RelayControllerIdentity(
            store: controllerThreadStore
        )
        let classifierThreadStore = RelayControllerThreadFileStore(
            fileURL: RelayControllerThreadFileStore
                .attentionClassifierFileURL
        )
        let classifierIdentity = RelayControllerIdentity(
            store: classifierThreadStore
        )
        let classifierSession = CodexControllerSessionAdapter(
            rpc: rpc,
            identity: classifierIdentity,
            cwd: Self.controllerWorkingDirectory,
            threadName: "Relay Attention Classifier"
        )
        let attentionInference = RelayAttentionInferenceCoordinator(
            aiClassifier: CodexAttentionClassifier(
                session: classifierSession
            )
        )
        let desktopFollowUpSender = CodexDesktopFollowUpSender()
        let taskClient = CodexTaskOperationsClient(
            rpc: rpc,
            sendToDesktopTask: { id, prompt in
                try await desktopFollowUpSender.send(
                    threadID: id,
                    prompt: prompt
                )
            }
        )
        let monitoringClient = CodexMonitoringClient(client: rpc)
        activityStore = RelayActivityStore(
            monitoring: monitoringClient,
            tasks: taskClient,
            controllerThreadStore: controllerThreadStore,
            additionalInternalThreadStores: [classifierThreadStore],
            attentionInference: attentionInference,
            connect: {
                try await rpc.start()
            },
            settings: settings
        )
        let pendingInteractionBroker = RelayPendingInteractionBroker(
            rpc: rpc,
            controllerIdentity: controllerIdentity
        )
        self.pendingInteractionBroker = pendingInteractionBroker
        let taskOperations = CodexRelayTaskOperationsAdapter(
            client: taskClient,
            controllerThreadStore: controllerThreadStore
        )
        let router = RelayToolCallRouter(
            operations: taskOperations,
            supervision: RelayControllerSupervisionAdapter(
                base: activityStore,
                pendingInteractions: {
                    await pendingInteractionBroker.interactions()
                }
            )
        )
        let controllerSession = CodexControllerSessionAdapter(
            rpc: rpc,
            identity: controllerIdentity,
            cwd: Self.controllerWorkingDirectory
        )
        let controllerRuntime = RelayControllerRuntime(
            session: controllerSession,
            router: router
        )
        let voiceSynthesizer = AppleSpeechSynthesizer(
            voiceIdentifier: settings.speechVoiceIdentifier,
            isEnabled: settings.speaksVoiceResponses,
            onSpeakingChange: { isSpeaking in
                Task { await onVoiceEvent(.speaking(isSpeaking)) }
            }
        )
        self.voiceSynthesizer = voiceSynthesizer
        let voiceSink = AppleSpeechCommandSink(
            commandHandler: controllerRuntime,
            synthesizer: voiceSynthesizer,
            shouldSpeakResponses: { [weak settings] in
                await MainActor.run {
                    settings?.speaksVoiceResponses ?? true
                }
            },
            onEvent: onVoiceEvent
        )

        commandHandler = controllerRuntime
        pushToTalk = PushToTalkCoordinator(
            microphone: AVAudioEngineMicrophoneCapture(),
            sink: voiceSink,
            onStateChange: onPushToTalkStateChange
        )
    }

    func startShortcut(
        handler: @escaping @MainActor @Sendable
            (RelayGlobalShortcutEvent) -> Void
    ) throws {
        try shortcutCoordinator.start(
            shortcut: settings.shortcut,
            handler: handler
        )
    }

    var activeShortcut: RelayGlobalShortcut? {
        shortcutCoordinator.activeShortcut
    }

    func applySettingsChange(_ change: RelaySettingsChange) throws {
        switch change {
        case let .shortcut(shortcut):
            try shortcutCoordinator.replaceShortcut(shortcut)
        case .speaksVoiceResponses, .speechVoiceIdentifier:
            voiceSynthesizer.configure(
                enabled: settings.speaksVoiceResponses,
                voiceIdentifier: settings.speechVoiceIdentifier
            )
        case let .autoApplyResetCredits(enabled):
            activityStore.autoApplyResetCredits = enabled
        case .showAtLaunch,
             .automaticPeeks,
             .followsPointerAcrossDisplays,
             .automaticallyChecksForUpdates,
             .updateCadence,
             .restoredDefaults:
            break
        }
    }

    isolated deinit {
        shortcutCoordinator.stop()
    }

    private static var controllerWorkingDirectory: String {
        let home = FileManager.default.homeDirectoryForCurrentUser
        let work = home.appendingPathComponent(
            "Work",
            isDirectory: true
        )
        var isDirectory: ObjCBool = false
        if FileManager.default.fileExists(
            atPath: work.path,
            isDirectory: &isDirectory
        ), isDirectory.boolValue {
            return work.path
        }
        return home.path
    }
}
