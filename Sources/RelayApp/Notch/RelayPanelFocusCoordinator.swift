import AppKit

@MainActor
final class RelayPanelFocusCoordinator {
    typealias ProcessIdentifier = pid_t

    private let relayProcessIdentifier: ProcessIdentifier
    private let frontmostProcessIdentifier: () -> ProcessIdentifier?
    private let activate: (ProcessIdentifier) -> Void
    private var previousProcessIdentifier: ProcessIdentifier?

    init(
        relayProcessIdentifier: ProcessIdentifier = ProcessInfo.processInfo
            .processIdentifier,
        frontmostProcessIdentifier: @escaping () -> ProcessIdentifier? = {
            NSWorkspace.shared.frontmostApplication?.processIdentifier
        },
        activate: @escaping (ProcessIdentifier) -> Void = { identifier in
            NSRunningApplication(processIdentifier: identifier)?.activate()
        }
    ) {
        self.relayProcessIdentifier = relayProcessIdentifier
        self.frontmostProcessIdentifier = frontmostProcessIdentifier
        self.activate = activate
    }

    func rememberFrontmostApplication() {
        guard previousProcessIdentifier == nil,
            let frontmost = frontmostProcessIdentifier(),
            frontmost != relayProcessIdentifier
        else {
            return
        }
        previousProcessIdentifier = frontmost
    }

    func restoreIfRelayStillOwnsFocus() {
        defer { previousProcessIdentifier = nil }
        guard frontmostProcessIdentifier() == relayProcessIdentifier,
            let previousProcessIdentifier
        else {
            return
        }
        activate(previousProcessIdentifier)
    }

    func discardRememberedApplication() {
        previousProcessIdentifier = nil
    }
}
