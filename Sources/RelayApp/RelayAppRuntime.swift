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

    private let shortcutMonitor: any RelayGlobalShortcutMonitoring

    init(
        onVoiceEvent: @escaping @Sendable
            (RelayVoiceControllerEvent) async -> Void,
        onPushToTalkStateChange: @escaping @MainActor @Sendable
            (PushToTalkState) -> Void
    ) {
        let rpc = PersistentCodexAppServerClient()
        let controllerThreadStore = RelayControllerThreadFileStore()
        let controllerIdentity = RelayControllerIdentity(
            store: controllerThreadStore
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
            connect: {
                try await rpc.start()
            }
        )
        pendingInteractionBroker = RelayPendingInteractionBroker(
            rpc: rpc,
            controllerIdentity: controllerIdentity
        )
        let taskOperations = CodexRelayTaskOperationsAdapter(
            client: taskClient,
            controllerThreadStore: controllerThreadStore
        )
        let router = RelayToolCallRouter(
            operations: taskOperations,
            supervision: activityStore
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
            onSpeakingChange: { isSpeaking in
                Task { await onVoiceEvent(.speaking(isSpeaking)) }
            }
        )
        let voiceSink = AppleSpeechCommandSink(
            commandHandler: controllerRuntime,
            synthesizer: voiceSynthesizer,
            onEvent: onVoiceEvent
        )

        commandHandler = controllerRuntime
        pushToTalk = PushToTalkCoordinator(
            microphone: AVAudioEngineMicrophoneCapture(),
            sink: voiceSink,
            onStateChange: onPushToTalkStateChange
        )
        shortcutMonitor = CarbonGlobalShortcutMonitor()
    }

    func startShortcut(
        handler: @escaping @MainActor @Sendable
            (RelayGlobalShortcutEvent) -> Void
    ) throws {
        try shortcutMonitor.start(
            shortcut: .default,
            handler: handler
        )
    }

    isolated deinit {
        shortcutMonitor.stop()
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
