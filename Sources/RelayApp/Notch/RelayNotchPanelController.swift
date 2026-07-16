import AppKit
import SwiftUI

@MainActor
final class RelayNotchPanelController {
    private let model: RelayAppModel
    private let panel: RelayNotchPanel
    private var globalClickMonitor: Any?
    private var localClickMonitor: Any?
    private var currentScreen: NSScreen?

    private(set) var presentation: RelayPanelPresentation = .hidden
    var shouldDismissOnOutsideClick: () -> Bool = { true }

    init(model: RelayAppModel) {
        self.model = model
        panel = RelayNotchPanel(
            contentRect: .zero,
            styleMask: [.borderless, .fullSizeContentView],
            backing: .buffered,
            defer: true
        )
        configurePanel()
        updateHost(for: .hidden)
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

        self.presentation = presentation
        currentScreen = targetScreen
        panel.relayPresentation = presentation
        updateHost(for: presentation)

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
            transition: presentation.transition(
                reduceMotion:
                    NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
            )
        )
        orderPanel(for: presentation)
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
        presentation = .hidden
        panel.relayPresentation = .hidden
        panel.orderOut(nil)
        currentScreen = nil
        removeOutsideClickMonitoring()
        updateHost(for: .hidden)
    }

    private func configurePanel() {
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

    private func updateHost(for presentation: RelayPanelPresentation) {
        panel.contentView = NSHostingView(
            rootView: RelayNotchPanelHost(
                model: model,
                presentation: presentation
            )
        )
    }

    private func orderPanel(for presentation: RelayPanelPresentation) {
        if presentation.allowsActivation {
            NSApplication.shared.activate()
            panel.makeKeyAndOrderFront(nil)
        } else {
            panel.orderFrontRegardless()
        }
    }

    private func apply(
        frame: CGRect,
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
        ) { [weak self] _ in
            Task { @MainActor in
                self?.dismissIfOutsidePanel(at: NSEvent.mouseLocation)
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
            !panel.frame.contains(location),
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
