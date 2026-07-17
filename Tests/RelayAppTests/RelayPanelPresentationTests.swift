import AppKit
import SwiftUI
import Testing
@testable import RelayApp

@MainActor
struct RelayPanelPresentationTests {
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
        #expect(RelayPanelPresentation.compact.collapsed == .hidden)
        #expect(RelayPanelPresentation.peek.collapsed == .hidden)
        #expect(RelayPanelPresentation.hidden.collapsed == .hidden)
    }

    @Test
    func automaticPeekDoesNotActivateButInteractiveSurfacesCan() {
        #expect(!RelayPanelPresentation.hidden.allowsActivation)
        #expect(!RelayPanelPresentation.peek.allowsActivation)
        #expect(RelayPanelPresentation.compact.allowsActivation)
        #expect(RelayPanelPresentation.expanded.allowsActivation)
    }

    @Test
    func panelsKeepSeparateNonactivatingAndInteractiveStyles() {
        let nonactivatingPanel = RelayNotchPanel(
            initialPresentation: .hidden
        )
        let interactivePanel = RelayNotchPanel(
            initialPresentation: .compact
        )

        nonactivatingPanel.updatePresentation(.peek)
        #expect(
            nonactivatingPanel.styleMask.contains(.nonactivatingPanel)
        )
        #expect(!nonactivatingPanel.canBecomeKey)

        interactivePanel.updatePresentation(.expanded)
        #expect(
            !interactivePanel.styleMask.contains(.nonactivatingPanel)
        )
        #expect(interactivePanel.canBecomeKey)
    }

    @Test
    func notchPanelHasNoRectangularWindowShadow() {
        let panel = RelayNotchPanel(initialPresentation: .compact)

        #expect(!panel.hasShadow)
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
            commandText: .constant(""),
            composerPhase: .idle,
            latestResponse: nil,
            connection: nil,
            submitCommand: {},
            retryConnection: {},
            submitPendingAnswers: { _, _ in },
            submitPendingDecision: { _, _ in },
            collapse: {}
        )

        _ = view
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
    func toggleOpensCompactAndThenDismisses() {
        #expect(RelayPanelPresentation.hidden.toggled == .compact)
        #expect(RelayPanelPresentation.peek.toggled == .compact)
        #expect(RelayPanelPresentation.compact.toggled == .hidden)
        #expect(RelayPanelPresentation.expanded.toggled == .hidden)
    }
}
