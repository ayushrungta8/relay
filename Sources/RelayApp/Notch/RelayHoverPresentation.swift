import Foundation

enum RelayHoverPresentation {
    static let collapseDelay = Duration.milliseconds(300)

    static func entryTarget(
        from presentation: RelayPanelPresentation
    ) -> RelayPanelPresentation? {
        switch presentation {
        case .peek, .compact:
            .expanded
        case .hidden, .expanded:
            nil
        }
    }

    static func exitTarget(
        from presentation: RelayPanelPresentation,
        draftsCanDismiss: Bool,
        pointerRemainsInside: Bool
    ) -> RelayPanelPresentation? {
        guard draftsCanDismiss,
              !pointerRemainsInside,
              presentation == .expanded else {
            return nil
        }
        return .compact
    }
}
