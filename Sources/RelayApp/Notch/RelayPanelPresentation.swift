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
        case .peek, .compact:
            .compact
        case .hidden:
            .hidden
        }
    }

    var toggled: Self {
        switch self {
        case .hidden, .peek:
            .expanded
        case .compact:
            .expanded
        case .expanded:
            .compact
        }
    }

    var allowsActivation: Bool {
        switch self {
        case .hidden, .peek, .compact:
            false
        case .expanded:
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
