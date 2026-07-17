import RelayCore
import SwiftUI
import Testing
@testable import RelayApp

struct RelayAccessibilityContractTests {
    @MainActor
    @Test
    func primaryControlsHaveStableVoiceOverLabels() {
        #expect(
            RelayAccessibilityContract.commandFieldLabel
                == "Command to Relay"
        )
        #expect(
            RelayAccessibilityContract.sendCommandLabel
                == "Send command"
        )
    }

    @MainActor
    @Test
    func keyboardShortcutReachesThePanelComposer() {
        #expect(
            RelayAccessibilityContract.sendCommandKeyEquivalent == .return
        )
    }

    @MainActor
    @Test
    func reduceMotionSelectsCrossfadeOnlyMotion() {
        #expect(
            RelayAccessibilityContract.motionStyle(reduceMotion: true)
                == .crossfade
        )
        #expect(
            RelayAccessibilityContract.motionStyle(reduceMotion: false)
                == .anchoredMovement
        )
        #expect(
            RelayPanelPresentation.expanded.transition(reduceMotion: true)
                == .crossfade(duration: 0.12)
        )
    }

    @MainActor
    @Test
    func reduceMotionDisablesLoopingStatusMotion() {
        #expect(
            RelayAccessibilityContract.allowsLoopingStatusMotion(
                reduceMotion: false
            )
        )
        #expect(
            !RelayAccessibilityContract.allowsLoopingStatusMotion(
                reduceMotion: true
            )
        )
    }

    @MainActor
    @Test
    func notchDropShapeKeepsTopFlushAndRoundsOnlyTheBottom() {
        let rect = CGRect(x: 0, y: 0, width: 400, height: 42)
        let path = RelayNotchDropShape(bottomRadius: 15).path(in: rect)

        #expect(path.contains(CGPoint(x: 1, y: 1)))
        #expect(path.contains(CGPoint(x: 399, y: 1)))
        #expect(!path.contains(CGPoint(x: 1, y: 41)))
        #expect(!path.contains(CGPoint(x: 399, y: 41)))
        #expect(path.contains(CGPoint(x: 200, y: 41)))
    }

    @MainActor
    @Test
    func everyStatusHasTextAndAShapeCueInsteadOfColorAlone() {
        let statuses = RelayAccessibilityContract.attentionStates.map {
            RelayAccessibilityContract.status(for: $0)
        }

        #expect(statuses.allSatisfy { !$0.label.isEmpty })
        #expect(statuses.allSatisfy { !$0.systemImage.isEmpty })
        #expect(Set(statuses.map(\.label)).count == statuses.count)
        #expect(Set(statuses.map(\.systemImage)).count == statuses.count)
        #expect(RelayPalette.idle == RelayPalette.tertiaryText)
    }
}
