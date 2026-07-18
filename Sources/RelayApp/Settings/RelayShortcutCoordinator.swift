import RelayVoice

@MainActor
final class RelayShortcutCoordinator {
    typealias MonitorFactory = @MainActor () ->
        any RelayGlobalShortcutMonitoring

    private let monitorFactory: MonitorFactory
    private var monitor: (any RelayGlobalShortcutMonitoring)?
    private var handler: (@MainActor @Sendable
        (RelayGlobalShortcutEvent) -> Void)?

    private(set) var activeShortcut: RelayGlobalShortcut?

    init(
        monitorFactory: @escaping MonitorFactory = {
            CarbonGlobalShortcutMonitor()
        }
    ) {
        self.monitorFactory = monitorFactory
    }

    func start(
        shortcut: RelayGlobalShortcut,
        handler: @escaping @MainActor @Sendable
            (RelayGlobalShortcutEvent) -> Void
    ) throws {
        let candidate = monitorFactory()
        try candidate.start(shortcut: shortcut, handler: handler)
        monitor?.stop()
        monitor = candidate
        activeShortcut = shortcut
        self.handler = handler
    }

    func replaceShortcut(_ shortcut: RelayGlobalShortcut) throws {
        guard let handler else { return }
        let candidate = monitorFactory()
        try candidate.start(shortcut: shortcut, handler: handler)
        monitor?.stop()
        monitor = candidate
        activeShortcut = shortcut
    }

    func stop() {
        monitor?.stop()
        monitor = nil
        handler = nil
        activeShortcut = nil
    }

    isolated deinit {
        monitor?.stop()
    }
}
