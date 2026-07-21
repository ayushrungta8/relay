import AppKit
import RelayVoice
import SwiftUI

@MainActor
final class RelayNotchPanelController {
    private let panel: RelayNotchPanel
    private let presentationState: RelayNotchPanelState
    private let hostingView: NSHostingView<RelayNotchPanelHost>
    private let settings: RelaySettingsStore
    private var globalClickMonitor: Any?
    private var localClickMonitor: Any?
    private var globalMouseMoveMonitor: Any?
    private var localMouseMoveMonitor: Any?
    private var screenParametersObserver: NSObjectProtocol?
    private var currentScreenIdentity: RelayScreenIdentity?
    private var relocationGeneration = 0
    private var hoverState = RelayPointerHoverState()
    private var hoverCollapseTask: Task<Void, Never>?
    private let focusCoordinator = RelayPanelFocusCoordinator()
    private let isVoiceSetupPresented: () -> Bool
    private let dismissVoiceSetup: () -> Void
    private lazy var displayFollower = RelayPointerDisplayFollower(
        relocate: { [weak self] identity in
            self?.relocateCompact(to: identity)
        }
    )
    private lazy var presentationCoordinator =
        RelayPanelPresentationCoordinator(
            presentPeek: { [weak self] in
                guard let self,
                      presentation == .hidden || presentation == .peek else {
                    return
                }
                present(.peek, on: screenContainingPointer())
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

    init(model: RelayAppModel, settings: RelaySettingsStore) {
        self.settings = settings
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
            self.present(value, on: currentScreenIdentity?.resolve())
        }
        presentationState.priorityActivityHandler = { [weak self] trigger in
            self?.presentationCoordinator.observe(trigger)
        }
        configurePanel(panel)
        panel.contentView = hostingView
        installPointerMonitoring()
    }

    func present(
        _ presentation: RelayPanelPresentation,
        on screen: NSScreen? = nil,
        restoreFocusOnDeactivation: Bool = true
    ) {
        guard presentation != .hidden else {
            dismiss()
            return
        }
        guard let targetScreen = screen ?? screenContainingActiveWindow() else {
            return
        }

        let wasActive = self.presentation.allowsActivation
        if presentation != .expanded {
            hoverState.reset()
        }

        relocationGeneration &+= 1
        panel.alphaValue = 1

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
        if wasActive && !presentation.allowsActivation {
            if restoreFocusOnDeactivation {
                focusCoordinator.restoreIfRelayStillOwnsFocus()
            } else {
                focusCoordinator.discardRememberedApplication()
            }
        }
        currentScreenIdentity = RelayScreenIdentity(screen: targetScreen)
        apply(
            frame: frame,
            transition: presentation.transition(
                reduceMotion:
                    NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
            )
        )
        installOutsideClickMonitoring()
        synchronizePointerDisplayFollowing()
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

    func applySettingsChange(_ change: RelaySettingsChange) {
        switch change {
        case let .followsPointerAcrossDisplays(enabled):
            if enabled {
                synchronizePointerDisplayFollowing()
            } else {
                displayFollower.cancel()
                relocationGeneration &+= 1
            }
        case .showAtLaunch,
             .automaticPeeks,
             .speaksVoiceResponses,
             .speechVoiceIdentifier,
             .shortcut,
             .automaticallyChecksForUpdates,
             .updateCadence,
             .autoApplyResetCredits,
             .controllerModel,
             .controllerReasoningEffort,
             .restoredDefaults:
            break
        }
    }

    func dismiss(restoreFocus: Bool = true) {
        guard presentationState.drafts.canDismiss else { return }
        let wasActive = presentation.allowsActivation
        presentationState.presentation = .hidden
        panel.updatePresentation(.hidden)
        panel.orderOut(nil)
        if wasActive {
            if restoreFocus {
                focusCoordinator.restoreIfRelayStillOwnsFocus()
            } else {
                focusCoordinator.discardRememberedApplication()
            }
        }
        currentScreenIdentity = nil
        hoverState.reset()
        displayFollower.cancel()
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
        panel.acceptsMouseMovedEvents = true
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
            focusCoordinator.rememberFrontmostApplication()
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
            present(target, on: currentScreenIdentity?.resolve())
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

    private func installPointerMonitoring() {
        globalMouseMoveMonitor = NSEvent.addGlobalMonitorForEvents(
            matching: .mouseMoved
        ) { [weak self] _ in
            Task { @MainActor in
                self?.synchronizePointerHover(at: NSEvent.mouseLocation)
                self?.synchronizePointerDisplayFollowing()
            }
        }
        localMouseMoveMonitor = NSEvent.addLocalMonitorForEvents(
            matching: .mouseMoved
        ) { [weak self] event in
            self?.synchronizePointerHover(at: NSEvent.mouseLocation)
            self?.synchronizePointerDisplayFollowing()
            return event
        }
        screenParametersObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.screenParametersDidChange()
            }
        }
    }

    private func synchronizePointerDisplayFollowing() {
        guard settings.followsPointerAcrossDisplays else {
            displayFollower.cancel()
            return
        }
        let pointerIdentity = screenAtPointer().flatMap {
            RelayScreenIdentity(screen: $0)
        }
        displayFollower.observe(
            pointerDisplay: pointerIdentity,
            currentDisplay: currentScreenIdentity,
            presentation: presentation
        )
    }

    private func synchronizePointerHover(at location: CGPoint) {
        let isInside = panel.isVisible
            && RelayPointerHoverState.contains(location, in: panel.frame)
        guard let change = hoverState.update(isInside: isInside) else {
            return
        }
        pointerHoverChanged(change)
    }

    private func screenParametersDidChange() {
        guard presentation != .hidden else { return }
        if let screen = currentScreenIdentity?.resolve() {
            present(presentation, on: screen)
        } else if let fallback = screenContainingPointer() ?? NSScreen.main {
            present(presentation, on: fallback)
        }
    }

    private func relocateCompact(to identity: RelayScreenIdentity) {
        guard
            settings.followsPointerAcrossDisplays,
            presentation == .compact,
            identity != currentScreenIdentity,
            let pointerScreen = screenAtPointer(),
            RelayScreenIdentity(screen: pointerScreen) == identity,
            let targetScreen = identity.resolve()
        else {
            synchronizePointerDisplayFollowing()
            return
        }

        displayFollower.cancel()
        relocationGeneration &+= 1
        let generation = relocationGeneration
        currentScreenIdentity = identity
        synchronizePointerDisplayFollowing()

        let frame = RelayNotchGeometry.frame(
            for: .compact,
            screenFrame: targetScreen.frame,
            visibleFrame: targetScreen.visibleFrame,
            safeAreaInsets: targetScreen.safeAreaInsets,
            leftAuxiliaryArea: targetScreen.auxiliaryTopLeftArea,
            rightAuxiliaryArea: targetScreen.auxiliaryTopRightArea
        )
        let duration = NSWorkspace.shared
            .accessibilityDisplayShouldReduceMotion
            ? 0.12
            : RelayPointerDisplayFollower.relocationDuration
        let safeArea = notchSafeArea(for: targetScreen)

        NSAnimationContext.runAnimationGroup { context in
            context.duration = duration / 2
            panel.animator().alphaValue = 0
        } completionHandler: { [weak self] in
            Task { @MainActor [weak self] in
                guard let self else { return }
                guard
                    relocationGeneration == generation,
                    presentation == .compact
                else {
                    panel.alphaValue = 1
                    return
                }

                panel.setFrame(frame, display: true)
                presentationState.notchSafeArea = safeArea
                NSAnimationContext.runAnimationGroup { context in
                    context.duration = duration / 2
                    panel.animator().alphaValue = 1
                }
            }
        }
    }

    private func dismissIfOutsidePanel(at location: CGPoint) {
        guard
            panel.isVisible,
            !RelayPointerHoverState.contains(location, in: panel.frame),
            shouldDismissOnOutsideClick()
        else {
            return
        }
        if isVoiceSetupPresented() {
            dismissVoiceSetup()
            return
        }
        if presentation == .expanded {
            present(
                .compact,
                on: currentScreenIdentity?.resolve(),
                restoreFocusOnDeactivation: false
            )
        } else if presentation == .peek {
            dismiss(restoreFocus: false)
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
            present(target, on: currentScreenIdentity?.resolve())
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
                && RelayPointerHoverState.contains(
                    NSEvent.mouseLocation,
                    in: panel.frame
                )
            guard let target = RelayHoverPresentation.exitTarget(
                from: presentation,
                draftsCanDismiss: presentationState.drafts.canDismiss,
                pointerRemainsInside: pointerRemainsInside
            ) else {
                return
            }
            present(target, on: currentScreenIdentity?.resolve())
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

    private func removePointerMonitoring() {
        displayFollower.cancel()
        if let globalMouseMoveMonitor {
            NSEvent.removeMonitor(globalMouseMoveMonitor)
            self.globalMouseMoveMonitor = nil
        }
        if let localMouseMoveMonitor {
            NSEvent.removeMonitor(localMouseMoveMonitor)
            self.localMouseMoveMonitor = nil
        }
        if let screenParametersObserver {
            NotificationCenter.default.removeObserver(screenParametersObserver)
            self.screenParametersObserver = nil
        }
    }

    private func screenAtPointer() -> NSScreen? {
        let pointer = NSEvent.mouseLocation
        return NSScreen.screens.first { $0.frame.contains(pointer) }
    }

    private func screenContainingPointer() -> NSScreen? {
        screenAtPointer() ?? NSScreen.main
    }

    private func screenContainingActiveWindow() -> NSScreen? {
        NSApplication.shared.keyWindow?.screen
            ?? NSApplication.shared.mainWindow?.screen
            ?? NSScreen.main
    }

    isolated deinit {
        hoverCollapseTask?.cancel()
        removeOutsideClickMonitoring()
        removePointerMonitoring()
    }
}
