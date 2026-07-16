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
