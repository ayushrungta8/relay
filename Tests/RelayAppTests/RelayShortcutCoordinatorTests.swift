import RelayVoice
import Testing
@testable import RelayApp

@MainActor
struct RelayShortcutCoordinatorTests {
    @Test
    func failedReplacementKeepsTheWorkingMonitorActive() throws {
        let first = ShortcutMonitorSpy()
        let rejected = ShortcutMonitorSpy(shouldFail: true)
        var monitors: [ShortcutMonitorSpy] = [first, rejected]
        let coordinator = RelayShortcutCoordinator {
            monitors.removeFirst()
        }

        try coordinator.start(shortcut: .optionSpace) { _ in }

        #expect(throws: ShortcutMonitorFailure.self) {
            try coordinator.replaceShortcut(
                RelayGlobalShortcut(
                    keyCode: 11,
                    modifiers: [.command, .shift]
                )
            )
        }

        #expect(first.stopCount == 0)
        #expect(rejected.stopCount == 0)
        #expect(coordinator.activeShortcut == .optionSpace)
    }

    @Test
    func successfulReplacementStopsThePreviousMonitorAfterRegistration()
        throws
    {
        let first = ShortcutMonitorSpy()
        let replacement = ShortcutMonitorSpy()
        var monitors: [ShortcutMonitorSpy] = [first, replacement]
        let coordinator = RelayShortcutCoordinator {
            monitors.removeFirst()
        }
        let shortcut = RelayGlobalShortcut(
            keyCode: 11,
            modifiers: [.command, .shift]
        )

        try coordinator.start(shortcut: .optionSpace) { _ in }
        try coordinator.replaceShortcut(shortcut)

        #expect(first.stopCount == 1)
        #expect(coordinator.activeShortcut == shortcut)
    }
}

@MainActor
private final class ShortcutMonitorSpy: RelayGlobalShortcutMonitoring {
    let shouldFail: Bool
    private(set) var stopCount = 0

    init(shouldFail: Bool = false) {
        self.shouldFail = shouldFail
    }

    func start(
        shortcut: RelayGlobalShortcut,
        handler: @escaping @MainActor @Sendable
            (RelayGlobalShortcutEvent) -> Void
    ) throws {
        if shouldFail { throw ShortcutMonitorFailure.rejected }
    }

    func stop() {
        stopCount += 1
    }
}

private enum ShortcutMonitorFailure: Error {
    case rejected
}
