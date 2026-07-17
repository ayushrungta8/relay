import RelayCore
import SwiftUI

enum RelayAccessibilityContract {
    enum MenuAction: CaseIterable, Equatable {
        case openRelay
        case openCodex
        case quit

        var title: String {
            switch self {
            case .openRelay:
                "Open Relay"
            case .openCodex:
                "Open Codex"
            case .quit:
                "Quit"
            }
        }

        var systemImage: String {
            switch self {
            case .openRelay:
                "arrow.left.arrow.right"
            case .openCodex:
                "arrow.up.forward.app"
            case .quit:
                "power"
            }
        }

        var keyEquivalent: KeyEquivalent? {
            switch self {
            case .openRelay:
                RelayAccessibilityContract.openRelayKeyEquivalent
            case .openCodex:
                nil
            case .quit:
                RelayAccessibilityContract.quitKeyEquivalent
            }
        }

        var modifiers: EventModifiers {
            switch self {
            case .openRelay:
                RelayAccessibilityContract.openRelayModifiers
            case .openCodex:
                []
            case .quit:
                RelayAccessibilityContract.quitModifiers
            }
        }
    }

    enum MotionStyle: Equatable {
        case crossfade
        case anchoredMovement
    }

    struct Status: Equatable {
        let label: String
        let systemImage: String
    }

    static let menuBarLabel = "Relay activity center"
    static let commandFieldLabel = "Command to Relay"
    static let sendCommandLabel = "Send command"
    static let openRelayKeyEquivalent: KeyEquivalent = "r"
    static let openRelayModifiers: EventModifiers = [.command, .shift]
    static let sendCommandKeyEquivalent = KeyEquivalent.return
    static let quitKeyEquivalent: KeyEquivalent = "q"
    static let quitModifiers: EventModifiers = .command

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
