import AppKit
import SwiftUI

@MainActor
final class RelayNotchPanelController {
    private let nonactivatingPanel: RelayNotchPanel
    private let interactivePanel: RelayNotchPanel
    private let presentationState: RelayNotchPanelState
    private let hostingView: NSHostingView<RelayNotchPanelHost>
    private var activePanel: RelayNotchPanel?
    private var globalClickMonitor: Any?
    private var localClickMonitor: Any?
    private var currentScreen: NSScreen?

    var presentation: RelayPanelPresentation {
        presentationState.presentation
    }
    var shouldDismissOnOutsideClick: () -> Bool = { true }

    init(model: RelayAppModel) {
        let presentationState = RelayNotchPanelState()
        self.presentationState = presentationState
        hostingView = NSHostingView(
            rootView: RelayNotchPanelHost(
                model: model,
                state: presentationState
            )
        )
        nonactivatingPanel = RelayNotchPanel(
            initialPresentation: .hidden
        )
        interactivePanel = RelayNotchPanel(
            initialPresentation: .compact
        )
        configurePanel(nonactivatingPanel)
        configurePanel(interactivePanel)
        nonactivatingPanel.contentView = hostingView
    }

    func present(
        _ presentation: RelayPanelPresentation,
        on screen: NSScreen? = nil
    ) {
        guard presentation != .hidden else {
            dismiss()
            return
        }
        guard let targetScreen = screen ?? screenContainingActiveWindow() else {
            return
        }

        let panel = panel(for: presentation)
        if activePanel !== panel {
            activePanel?.orderOut(nil)
        }
        attachHost(to: panel)
        activePanel = panel
        presentationState.presentation = presentation
        currentScreen = targetScreen
        panel.updatePresentation(presentation)

        let frame = RelayNotchGeometry.frame(
            for: presentation,
            screenFrame: targetScreen.frame,
            visibleFrame: targetScreen.visibleFrame,
            safeAreaInsets: targetScreen.safeAreaInsets,
            leftAuxiliaryArea: targetScreen.auxiliaryTopLeftArea,
            rightAuxiliaryArea: targetScreen.auxiliaryTopRightArea
        )
        apply(
            frame: frame,
            to: panel,
            transition: presentation.transition(
                reduceMotion:
                    NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
            )
        )
        orderPanel(panel, for: presentation)
        installOutsideClickMonitoring()
    }

    func toggle(on screen: NSScreen? = nil) {
        let target = presentation.toggled
        guard target != .hidden else {
            dismiss()
            return
        }
        present(target, on: screen ?? screenContainingPointer())
    }

    func dismiss() {
        presentationState.presentation = .hidden
        if activePanel === nonactivatingPanel {
            nonactivatingPanel.updatePresentation(.hidden)
        }
        activePanel?.orderOut(nil)
        activePanel = nil
        currentScreen = nil
        removeOutsideClickMonitoring()
    }

    private func configurePanel(_ panel: RelayNotchPanel) {
        panel.level = .statusBar
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = true
        panel.isMovable = false
        panel.isMovableByWindowBackground = false
        panel.hidesOnDeactivate = false
        panel.isFloatingPanel = true
        panel.animationBehavior = .none
        panel.collectionBehavior = [
            .canJoinAllSpaces,
            .fullScreenAuxiliary,
            .stationary,
        ]
        panel.escapeHandler = { [weak self] in
            self?.collapseOneLevel()
        }
    }

    private func attachHost(to panel: RelayNotchPanel) {
        guard panel.contentView !== hostingView else { return }

        nonactivatingPanel.contentView = nil
        interactivePanel.contentView = nil
        panel.contentView = hostingView
    }

    private func panel(
        for presentation: RelayPanelPresentation
    ) -> RelayNotchPanel {
        if presentation.allowsActivation {
            interactivePanel
        } else {
            nonactivatingPanel
        }
    }

    private func orderPanel(
        _ panel: RelayNotchPanel,
        for presentation: RelayPanelPresentation
    ) {
        if presentation.allowsActivation {
            NSApplication.shared.activate()
            panel.makeKeyAndOrderFront(nil)
        } else {
            panel.orderFrontRegardless()
        }
    }

    private func apply(
        frame: CGRect,
        to panel: RelayNotchPanel,
        transition: RelayPanelPresentation.Transition
    ) {
        switch transition {
        case let .crossfade(duration):
            panel.alphaValue = 0
            panel.setFrame(frame, display: true)
            NSAnimationContext.runAnimationGroup { context in
                context.duration = duration
                panel.animator().alphaValue = 1
            }
        case let .anchoredResize(duration):
            guard panel.isVisible else {
                panel.setFrame(collapsedFrame(for: frame), display: false)
                NSAnimationContext.runAnimationGroup { context in
                    context.duration = duration
                    context.timingFunction = CAMediaTimingFunction(
                        name: .easeOut
                    )
                    panel.animator().setFrame(frame, display: true)
                }
                return
            }

            NSAnimationContext.runAnimationGroup { context in
                context.duration = duration
                context.timingFunction = CAMediaTimingFunction(name: .easeOut)
                panel.animator().setFrame(frame, display: true)
            }
        }
    }

    private func collapsedFrame(for frame: CGRect) -> CGRect {
        CGRect(
            x: frame.midX,
            y: frame.maxY,
            width: 0,
            height: 0
        )
    }

    private func collapseOneLevel() {
        let target = presentation.collapsed
        if target == .hidden {
            dismiss()
        } else {
            present(target, on: currentScreen)
        }
    }

    private func installOutsideClickMonitoring() {
        guard globalClickMonitor == nil, localClickMonitor == nil else {
            return
        }

        let eventMask: NSEvent.EventTypeMask = [
            .leftMouseDown,
            .rightMouseDown,
            .otherMouseDown,
        ]
        globalClickMonitor = NSEvent.addGlobalMonitorForEvents(
            matching: eventMask
        ) { [weak self] event in
            let click = RelayPanelClick(globalEvent: event)
            Task { @MainActor in
                self?.dismissIfOutsidePanel(at: click.screenLocation)
            }
        }
        localClickMonitor = NSEvent.addLocalMonitorForEvents(
            matching: eventMask
        ) { [weak self] event in
            self?.dismissIfOutsidePanel(at: NSEvent.mouseLocation)
            return event
        }
    }

    private func dismissIfOutsidePanel(at location: CGPoint) {
        guard
            let activePanel,
            !activePanel.frame.contains(location),
            shouldDismissOnOutsideClick()
        else {
            return
        }
        dismiss()
    }

    private func removeOutsideClickMonitoring() {
        if let globalClickMonitor {
            NSEvent.removeMonitor(globalClickMonitor)
            self.globalClickMonitor = nil
        }
        if let localClickMonitor {
            NSEvent.removeMonitor(localClickMonitor)
            self.localClickMonitor = nil
        }
    }

    private func screenContainingPointer() -> NSScreen? {
        let pointer = NSEvent.mouseLocation
        return NSScreen.screens.first { $0.frame.contains(pointer) }
            ?? NSScreen.main
    }

    private func screenContainingActiveWindow() -> NSScreen? {
        NSApplication.shared.keyWindow?.screen
            ?? NSApplication.shared.mainWindow?.screen
            ?? NSScreen.main
    }

    isolated deinit {
        removeOutsideClickMonitoring()
    }
}
