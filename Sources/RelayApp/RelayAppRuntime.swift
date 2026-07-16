import Foundation
import RelayBrain
import RelayCodexBridge
import RelayCodexClient
import RelayVoice

@MainActor
final class RelayAppRuntime {
    let commandHandler: any RelayCommandHandling
    let pushToTalk: PushToTalkCoordinator

    private let shortcutMonitor: any RelayGlobalShortcutMonitoring

    init(
        onVoiceEvent: @escaping @Sendable
            (RelayVoiceControllerEvent) async -> Void,
        onPushToTalkStateChange: @escaping @MainActor @Sendable
            (PushToTalkState) -> Void
    ) {
        let rpc = PersistentCodexAppServerClient()
        let controllerThreadStore = RelayControllerThreadFileStore()
        let taskClient = CodexTaskOperationsClient(rpc: rpc)
        let taskOperations = CodexRelayTaskOperationsAdapter(
            client: taskClient,
            controllerThreadStore: controllerThreadStore
        )
        let router = RelayToolCallRouter(operations: taskOperations)
        let controllerSession = CodexControllerSessionAdapter(
            rpc: rpc,
            store: controllerThreadStore,
            cwd: Self.controllerWorkingDirectory
        )
        let controllerRuntime = RelayControllerRuntime(
            session: controllerSession,
            router: router
        )
        let voiceSink = AppleSpeechCommandSink(
            commandHandler: controllerRuntime,
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
