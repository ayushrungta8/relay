import AppKit
import SwiftUI
import Testing
@testable import RelayApp

@MainActor
struct RelayPanelPresentationTests {
    @Test
    func compactIsThePersistentNonactivatingLaunchState() {
        #expect(RelayApplicationPresentation.launchPresentation == .compact)
        #expect(RelayApplicationPresentation.activationPolicy == .accessory)
        #expect(!RelayPanelPresentation.compact.allowsActivation)
        #expect(RelayPanelPresentation.expanded.allowsActivation)
    }

    @Test
    func hoverExpandsAndPointerExitReturnsToCompact() {
        #expect(
            RelayHoverPresentation.entryTarget(from: .compact) == .expanded
        )
        #expect(
            RelayHoverPresentation.exitTarget(
                from: .expanded,
                draftsCanDismiss: true,
                pointerRemainsInside: false
            ) == .compact
        )
        #expect(
            RelayHoverPresentation.exitTarget(
                from: .expanded,
                draftsCanDismiss: false,
                pointerRemainsInside: false
            ) == nil
        )
        #expect(
            RelayHoverPresentation.exitTarget(
                from: .expanded,
                draftsCanDismiss: true,
                pointerRemainsInside: true
            ) == nil
        )
        #expect(RelayHoverPresentation.collapseDelay == .milliseconds(300))
    }

    @Test
    func escalationMovesThroughEveryPresentationLevel() {
        #expect(RelayPanelPresentation.hidden.escalated == .peek)
        #expect(RelayPanelPresentation.peek.escalated == .compact)
        #expect(RelayPanelPresentation.compact.escalated == .expanded)
        #expect(RelayPanelPresentation.expanded.escalated == .expanded)
    }

    @Test
    func escapeCollapsesOneLevelBeforeDismissing() {
        #expect(RelayPanelPresentation.expanded.collapsed == .compact)
        #expect(RelayPanelPresentation.compact.collapsed == .compact)
        #expect(RelayPanelPresentation.peek.collapsed == .compact)
        #expect(RelayPanelPresentation.hidden.collapsed == .hidden)
    }

    @Test
    func automaticPeekDoesNotActivateButInteractiveSurfacesCan() {
        #expect(!RelayPanelPresentation.hidden.allowsActivation)
        #expect(!RelayPanelPresentation.peek.allowsActivation)
        #expect(!RelayPanelPresentation.compact.allowsActivation)
        #expect(RelayPanelPresentation.expanded.allowsActivation)
    }

    @Test
    func panelKeepsAStableNonactivatingStyleWhilePresentationControlsKeyState() {
        let panel = RelayNotchPanel(
            initialPresentation: .hidden
        )

        panel.updatePresentation(.compact)
        #expect(
            panel.styleMask.contains(.nonactivatingPanel)
        )
        #expect(!panel.canBecomeKey)

        panel.updatePresentation(.expanded)
        #expect(
            panel.styleMask.contains(.nonactivatingPanel)
        )
        #expect(panel.canBecomeKey)
    }

    @Test
    func notchPanelHasNoRectangularWindowShadow() {
        let panel = RelayNotchPanel(initialPresentation: .compact)

        #expect(!panel.hasShadow)
    }

    @Test
    func notchPanelPreservesThePhysicalTopEdgeFrame() throws {
        let screen = try #require(NSScreen.main)
        let proposedFrame = CGRect(
            x: screen.frame.midX - 360,
            y: screen.frame.maxY - 470,
            width: 720,
            height: 470
        )
        let panel = RelayNotchPanel(initialPresentation: .expanded)

        #expect(
            panel.constrainFrameRect(proposedFrame, to: screen)
                == proposedFrame
        )
    }

    @Test
    func screenIdentityRoundTripsTheMainDisplay() throws {
        let screen = try #require(NSScreen.main)
        let identity = try #require(RelayScreenIdentity(screen: screen))

        #expect(identity.resolve() === screen)
    }

    @Test
    func pointerFollowingUsesApprovedTiming() {
        #expect(
            RelayPointerDisplayFollower.dwellDelay == .milliseconds(500)
        )
        #expect(RelayPointerDisplayFollower.relocationDuration == 0.16)
    }

    @Test
    func floatingNotchPanelRendersAboveFullscreenWindows() {
        let panel = RelayNotchPanel(initialPresentation: .expanded)

        #expect(panel.isFloatingPanel)
        #expect(panel.level == .screenSaver)
    }

    @Test
    func expandedPanelUsesUnconditionalFrontOrderingBeforeTakingKeyFocus()
        throws
    {
        let controllerSource = try relayProjectSource(
            "Sources/RelayApp/Notch/RelayNotchPanelController.swift"
        )

        #expect(
            controllerSource.contains(
                "panel.orderFrontRegardless()\n            panel.makeKey()"
            )
        )
    }

    @Test
    func globalClickCapturesTheEventsScreenLocation() throws {
        let eventLocation = CGPoint(x: -340, y: 712)
        let event = try #require(
            NSEvent.mouseEvent(
                with: .leftMouseDown,
                location: eventLocation,
                modifierFlags: [],
                timestamp: 42,
                windowNumber: 0,
                context: nil,
                eventNumber: 1,
                clickCount: 1,
                pressure: 1
            )
        )

        let click = RelayPanelClick(globalEvent: event)

        #expect(click.screenLocation == eventLocation)
    }

    @Test
    func hostPresentationUpdatesThroughPersistentReferenceState() {
        let model = RelayAppModel()
        let state = RelayNotchPanelState()
        let hostingView = NSHostingView(
            rootView: RelayNotchPanelHost(model: model, state: state)
        )
        let hostIdentity = ObjectIdentifier(hostingView)

        state.presentation = .compact
        state.presentation = .expanded

        #expect(ObjectIdentifier(hostingView) == hostIdentity)
        #expect(hostingView.rootView.state === state)
        #expect(hostingView.rootView.state.presentation == .expanded)
    }

    @Test
    func cameraObstructionReceivesSideClearance() {
        let safeArea = RelayNotchSafeArea(
            topInset: 38,
            obstructionWidth: 224
        )

        #expect(safeArea.contentClearanceWidth == 248)
        #expect(
            RelayNotchSafeArea(topInset: 0, obstructionWidth: 0)
                .contentClearanceWidth == 190
        )
    }

    @Test
    func hostingViewDoesNotPublishWindowSizingConstraints() {
        let host = NSHostingView(rootView: Color.clear)

        RelayHostingViewConfiguration.apply(to: host)

        #expect(host.sizingOptions.isEmpty)
        #expect(host.safeAreaRegions.isEmpty)
        #expect(host.autoresizingMask == [.width, .height])
    }

    @Test
    func expandedSurfaceHasNoWindowSizingFeedbackCallback() {
        let view = RelayExpandedActivityView(
            activity: RelayActivityPresentation(tasks: []),
            capacity: RelayCapacityPresentation(snapshot: nil),
            tokenUsageByThreadID: [:],
            pendingInteractions: [],
            drafts: RelayPanelDraftStore(),
            actions: RelayTaskActions(
                select: { _ in },
                open: { _ in },
                markRead: { _ in },
                send: { _, _ in },
                interrupt: { _ in }
            ),
            usageActions: RelayUsageActions(
                applyResetCredit: { _ in },
                setAutoApplyResetCredits: { _ in }
            ),
            autoApplyResetCredits: false,
            selectedSection: .constant(.activity),
            commandText: .constant(""),
            composerPhase: .idle,
            chatMessages: [],
            connection: nil,
            safeArea: RelayNotchSafeArea(
                topInset: 38,
                obstructionWidth: 224
            ),
            submitCommand: {},
            retryConnection: {},
            submitPendingAnswers: { _, _ in },
            submitPendingDecision: { _, _ in },
            collapse: {}
        )

        _ = view
    }

    @Test
    func expandedSectionPreservesUserSelectionWithoutANewChatMessage() {
        let selection = RelayExpandedSection.selection(
            preserving: .activity,
            previousChatMessageCount: 2,
            chatMessageCount: 2
        )

        #expect(selection == .activity)
    }

    @Test
    func expandedSectionOpensChatWhenANewMessageArrives() {
        let selection = RelayExpandedSection.selection(
            preserving: .usage,
            previousChatMessageCount: 2,
            chatMessageCount: 3
        )

        #expect(selection == .chat)
    }

    @Test
    func swiftUIRequestsPresentationWithoutMutatingPanelStateDirectly() {
        let state = RelayNotchPanelState()
        state.presentation = .compact
        var requestedPresentation: RelayPanelPresentation?
        state.presentationRequestHandler = { presentation in
            requestedPresentation = presentation
        }

        state.requestPresentation(.expanded)

        #expect(state.presentation == .compact)
        #expect(requestedPresentation == .expanded)
    }

    @Test
    func panelStatePublishesNotchSafeAreaToSwiftUI() {
        let state = RelayNotchPanelState()
        let safeArea = RelayNotchSafeArea(
            topInset: 38,
            obstructionWidth: 224
        )

        state.notchSafeArea = safeArea

        #expect(state.notchSafeArea == safeArea)
    }

    @Test
    func reduceMotionSelectsCrossfadeInsteadOfAnchoredResize() {
        #expect(
            RelayPanelPresentation.expanded.transition(reduceMotion: true)
                == .crossfade(duration: 0.12)
        )
        #expect(
            RelayPanelPresentation.expanded.transition(reduceMotion: false)
                == .anchoredResize(duration: 0.22)
        )
    }

    @Test
    func directInvocationTogglesBetweenExpandedAndCompact() {
        #expect(RelayPanelPresentation.hidden.toggled == .expanded)
        #expect(RelayPanelPresentation.peek.toggled == .expanded)
        #expect(RelayPanelPresentation.compact.toggled == .expanded)
        #expect(RelayPanelPresentation.expanded.toggled == .compact)
    }
}

private func relayProjectSource(_ relativePath: String) throws -> String {
    let root = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()
    return try String(
        contentsOf: root.appendingPathComponent(relativePath),
        encoding: .utf8
    )
}
