import Darwin
import Testing

@testable import RelayApp

@MainActor
struct RelayPanelFocusCoordinatorTests {
    @Test
    func restoresPreviousApplicationWhenRelayStillOwnsFocus() {
        var frontmost: pid_t? = 41
        var activated: [pid_t] = []
        let coordinator = RelayPanelFocusCoordinator(
            relayProcessIdentifier: 99,
            frontmostProcessIdentifier: { frontmost },
            activate: { activated.append($0) }
        )

        coordinator.rememberFrontmostApplication()
        frontmost = 99
        coordinator.restoreIfRelayStillOwnsFocus()

        #expect(activated == [41])
    }

    @Test
    func doesNotOverrideApplicationActivatedByOutsideClick() {
        var frontmost: pid_t? = 41
        var activated: [pid_t] = []
        let coordinator = RelayPanelFocusCoordinator(
            relayProcessIdentifier: 99,
            frontmostProcessIdentifier: { frontmost },
            activate: { activated.append($0) }
        )

        coordinator.rememberFrontmostApplication()
        frontmost = 52
        coordinator.restoreIfRelayStillOwnsFocus()

        #expect(activated.isEmpty)
    }

    @Test
    func discardingFocusPreventsLaterRestoration() {
        var frontmost: pid_t? = 41
        var activated: [pid_t] = []
        let coordinator = RelayPanelFocusCoordinator(
            relayProcessIdentifier: 99,
            frontmostProcessIdentifier: { frontmost },
            activate: { activated.append($0) }
        )

        coordinator.rememberFrontmostApplication()
        coordinator.discardRememberedApplication()
        frontmost = 99
        coordinator.restoreIfRelayStillOwnsFocus()

        #expect(activated.isEmpty)
    }
}
