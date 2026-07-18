import AppKit

final class RelayNotchPanel: NSPanel {
    private(set) var relayPresentation: RelayPanelPresentation
    var escapeHandler: (() -> Void)?

    init(initialPresentation: RelayPanelPresentation) {
        relayPresentation = initialPresentation

        let styleMask: NSWindow.StyleMask = [
            .borderless,
            .fullSizeContentView,
            .nonactivatingPanel,
        ]

        super.init(
            contentRect: .zero,
            styleMask: styleMask,
            backing: .buffered,
            defer: true
        )
        isFloatingPanel = true
        level = .screenSaver
        hasShadow = false
    }

    override var canBecomeKey: Bool {
        relayPresentation.allowsActivation
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
        relayPresentation = presentation
    }

    override func cancelOperation(_ sender: Any?) {
        escapeHandler?()
    }
}
