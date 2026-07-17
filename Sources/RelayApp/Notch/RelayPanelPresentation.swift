import Foundation

enum RelayPanelPresentation: Int, CaseIterable, Sendable {
    enum Transition: Equatable, Sendable {
        case anchoredResize(duration: TimeInterval)
        case crossfade(duration: TimeInterval)
    }

    case hidden
    case peek
    case compact
    case expanded

    var escalated: Self {
        switch self {
        case .hidden:
            .peek
        case .peek:
            .compact
        case .compact, .expanded:
            .expanded
        }
    }

    var collapsed: Self {
        switch self {
        case .expanded:
            .compact
        case .hidden, .peek, .compact:
            .hidden
        }
    }

    var toggled: Self {
        switch self {
        case .hidden, .peek:
            .expanded
        case .compact, .expanded:
            .hidden
        }
    }

    var allowsActivation: Bool {
        switch self {
        case .hidden, .peek:
            false
        case .compact, .expanded:
            true
        }
    }

    func transition(reduceMotion: Bool) -> Transition {
        if reduceMotion {
            .crossfade(duration: 0.12)
        } else {
            .anchoredResize(duration: 0.22)
        }
    }
}
