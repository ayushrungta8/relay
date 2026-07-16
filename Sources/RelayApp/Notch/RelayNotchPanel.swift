import AppKit

final class RelayNotchPanel: NSPanel {
    var relayPresentation: RelayPanelPresentation = .hidden
    var escapeHandler: (() -> Void)?

    override var canBecomeKey: Bool {
        relayPresentation.allowsActivation
    }

    override var canBecomeMain: Bool {
        false
    }

    override func cancelOperation(_ sender: Any?) {
        escapeHandler?()
    }
}
