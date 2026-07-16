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
