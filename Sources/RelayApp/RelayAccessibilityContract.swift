import RelayCore
import SwiftUI

enum RelayAccessibilityContract {
    enum MotionStyle: Equatable {
        case crossfade
        case anchoredMovement
    }

    struct Status: Equatable {
        let label: String
        let systemImage: String
    }

    static let commandFieldLabel = "Command to Relay"
    static let sendCommandLabel = "Send command"
    static let sendCommandKeyEquivalent = KeyEquivalent.return

    static let attentionStates: [RelayTaskAttentionState] = [
        .needsInput,
        .failed,
        .ready,
        .running,
        .idle,
    ]

    static func motionStyle(reduceMotion: Bool) -> MotionStyle {
        reduceMotion ? .crossfade : .anchoredMovement
    }

    static func allowsLoopingStatusMotion(reduceMotion: Bool) -> Bool {
        !reduceMotion
    }

    static func status(for state: RelayTaskAttentionState) -> Status {
        switch state {
        case .needsInput:
            Status(
                label: "Needs input",
                systemImage: "exclamationmark.bubble.fill"
            )
        case .failed:
            Status(label: "Failed", systemImage: "xmark.octagon.fill")
        case .ready:
            Status(label: "Ready", systemImage: "checkmark.circle.fill")
        case .running:
            Status(label: "Running", systemImage: "ellipsis.circle.fill")
        case .idle:
            Status(label: "Idle", systemImage: "clock.fill")
        }
    }
}
