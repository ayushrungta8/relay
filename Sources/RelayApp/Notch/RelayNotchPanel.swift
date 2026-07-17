import AppKit

final class RelayNotchPanel: NSPanel {
    private let activationPolicyAllowsActivation: Bool
    private(set) var relayPresentation: RelayPanelPresentation
    var escapeHandler: (() -> Void)?

    init(initialPresentation: RelayPanelPresentation) {
        activationPolicyAllowsActivation =
            initialPresentation.allowsActivation
        relayPresentation = initialPresentation

        var styleMask: NSWindow.StyleMask = [
            .borderless,
            .fullSizeContentView,
        ]
        if !activationPolicyAllowsActivation {
            styleMask.insert(.nonactivatingPanel)
        }

        super.init(
            contentRect: .zero,
            styleMask: styleMask,
            backing: .buffered,
            defer: true
        )
        level = .screenSaver
        hasShadow = false
    }

    override var canBecomeKey: Bool {
        activationPolicyAllowsActivation
            && relayPresentation.allowsActivation
    }

    override var canBecomeMain: Bool {
        false
    }

    /// AppKit normally constrains panels to the visible frame below the menu
    /// bar. Relay owns physical-screen placement so its surface can meet the
    /// top edge and flow around the camera housing.
    override func constrainFrameRect(
        _ frameRect: NSRect,
        to screen: NSScreen?
    ) -> NSRect {
        frameRect
    }

    func updatePresentation(
        _ presentation: RelayPanelPresentation
    ) {
        precondition(
            presentation.allowsActivation
                == activationPolicyAllowsActivation,
            "A Relay panel cannot change its activation policy."
        )
        relayPresentation = presentation
    }

    override func cancelOperation(_ sender: Any?) {
        escapeHandler?()
    }
}
