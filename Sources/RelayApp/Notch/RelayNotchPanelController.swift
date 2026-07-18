import AppKit
import RelayVoice
import SwiftUI

@MainActor
final class RelayNotchPanelController {
    private let panel: RelayNotchPanel
    private let presentationState: RelayNotchPanelState
    private let hostingView: NSHostingView<RelayNotchPanelHost>
    private var globalClickMonitor: Any?
    private var localClickMonitor: Any?
    private var currentScreen: NSScreen?
    private var hoverCollapseTask: Task<Void, Never>?
    private let isVoiceSetupPresented: () -> Bool
    private let dismissVoiceSetup: () -> Void
    private lazy var presentationCoordinator =
        RelayPanelPresentationCoordinator(
            presentPeek: { [weak self] in
                guard let self,
                      presentation == .hidden || presentation == .peek else {
                    return
                }
                present(.peek)
            },
            dismissPeek: { [weak self] in
                guard let self, presentation == .peek else { return }
                dismiss()
            }
        )

    var presentation: RelayPanelPresentation {
        presentationState.presentation
    }
    var shouldDismissOnOutsideClick: () -> Bool

    init(model: RelayAppModel) {
        let presentationState = RelayNotchPanelState()
        self.presentationState = presentationState
        isVoiceSetupPresented = { model.voiceSetup != nil }
        dismissVoiceSetup = model.dismissVoiceSetup
        shouldDismissOnOutsideClick = { presentationState.drafts.canDismiss }
        let hostingView = NSHostingView(
            rootView: RelayNotchPanelHost(
                model: model,
                state: presentationState
            )
        )
        RelayHostingViewConfiguration.apply(to: hostingView)
        self.hostingView = hostingView
        panel = RelayNotchPanel(
            initialPresentation: .hidden
        )
        presentationState.presentationRequestHandler = { [weak self] value in
            guard let self else { return }
            self.present(value, on: currentScreen)
        }
        presentationState.priorityActivityHandler = { [weak self] trigger in
            self?.presentationCoordinator.observe(trigger)
        }
        presentationState.pointerHoverHandler = { [weak self] isInside in
            self?.pointerHoverChanged(isInside)
        }
        configurePanel(panel)
        panel.contentView = hostingView
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

        let frame = RelayNotchGeometry.frame(
            for: presentation,
            screenFrame: targetScreen.frame,
            visibleFrame: targetScreen.visibleFrame,
            safeAreaInsets: targetScreen.safeAreaInsets,
            leftAuxiliaryArea: targetScreen.auxiliaryTopLeftArea,
            rightAuxiliaryArea: targetScreen.auxiliaryTopRightArea
        )
        if !panel.isVisible {
            panel.setFrame(collapsedFrame(for: frame), display: false)
        }
        panel.updatePresentation(presentation)
        orderPanel(panel, for: presentation)
        presentationState.notchSafeArea = notchSafeArea(for: targetScreen)
        presentationState.presentation = presentation
        currentScreen = targetScreen
        apply(
            frame: frame,
            transition: presentation.transition(
                reduceMotion:
                    NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
            )
        )
        installOutsideClickMonitoring()
    }

    func toggle(on screen: NSScreen? = nil) {
        presentationCoordinator.cancelAutomaticDismissal()
        guard let target = presentationState.toggleTarget() else { return }
        guard target != .hidden else {
            dismiss()
            return
        }
        present(target, on: screen ?? screenContainingPointer())
    }

    func presentDefaultCompact() {
        present(
            RelayApplicationPresentation.launchPresentation,
            on: screenContainingPointer()
        )
    }

    func dismiss() {
        guard presentationState.drafts.canDismiss else { return }
        presentationState.presentation = .hidden
        panel.updatePresentation(.hidden)
        panel.orderOut(nil)
        currentScreen = nil
        removeOutsideClickMonitoring()
    }

    private func configurePanel(_ panel: RelayNotchPanel) {
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = false
        panel.isMovable = false
        panel.isMovableByWindowBackground = false
        panel.hidesOnDeactivate = false
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

    private func orderPanel(
        _ panel: RelayNotchPanel,
        for presentation: RelayPanelPresentation
    ) {
        if presentation.allowsActivation {
            NSApplication.shared.activate()
            panel.orderFrontRegardless()
            panel.makeKey()
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
            if !panel.isVisible {
                panel.setFrame(collapsedFrame(for: frame), display: false)
            }
            NSAnimationContext.animate(
                .spring(duration: max(duration, 0.24), bounce: 0.08)
            ) {
                panel.setFrame(frame, display: true)
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

    private func notchSafeArea(for screen: NSScreen) -> RelayNotchSafeArea {
        let obstructionWidth = if
            let leftArea = screen.auxiliaryTopLeftArea,
            let rightArea = screen.auxiliaryTopRightArea
        {
            Double(max(0, rightArea.minX - leftArea.maxX))
        } else {
            0.0
        }

        return RelayNotchSafeArea(
            topInset: screen.safeAreaInsets.top,
            obstructionWidth: obstructionWidth
        )
    }

    private func collapseOneLevel() {
        if isVoiceSetupPresented() {
            dismissVoiceSetup()
            return
        }
        guard presentationState.drafts.canDismiss else { return }
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
            panel.isVisible,
            !panel.frame.contains(location),
            shouldDismissOnOutsideClick()
        else {
            return
        }
        if isVoiceSetupPresented() {
            dismissVoiceSetup()
            return
        }
        if presentation == .expanded {
            present(.compact, on: currentScreen)
        } else if presentation == .peek {
            dismiss()
        }
    }

    private func pointerHoverChanged(_ isInside: Bool) {
        hoverCollapseTask?.cancel()
        hoverCollapseTask = nil

        if isInside {
            guard let target = RelayHoverPresentation.entryTarget(
                from: presentation
            ) else {
                return
            }
            present(target, on: currentScreen)
            return
        }

        guard !isVoiceSetupPresented() else { return }

        hoverCollapseTask = Task { [weak self] in
            do {
                try await Task.sleep(
                    for: RelayHoverPresentation.collapseDelay
                )
            } catch {
                return
            }
            guard
                let self,
                !Task.isCancelled,
                !isVoiceSetupPresented()
            else {
                return
            }
            let pointerRemainsInside = panel.isVisible
                && panel.frame.contains(NSEvent.mouseLocation)
            guard let target = RelayHoverPresentation.exitTarget(
                from: presentation,
                draftsCanDismiss: presentationState.drafts.canDismiss,
                pointerRemainsInside: pointerRemainsInside
            ) else {
                return
            }
            present(target, on: currentScreen)
        }
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
        hoverCollapseTask?.cancel()
        removeOutsideClickMonitoring()
    }
}
