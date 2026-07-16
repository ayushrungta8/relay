import Observation

@MainActor
@Observable
final class RelayNotchPanelState {
    var presentation: RelayPanelPresentation = .hidden
    var topInset: Double = 0
    @ObservationIgnored
    var presentationRequestHandler:
        ((RelayPanelPresentation) -> Void)?
    @ObservationIgnored
    var contentHeightRequestHandler:
        ((RelayPanelPresentation, Double) -> Void)?

    func requestPresentation(
        _ presentation: RelayPanelPresentation
    ) {
        presentationRequestHandler?(presentation)
    }

    func requestContentHeight(
        _ height: Double,
        for presentation: RelayPanelPresentation
    ) {
        contentHeightRequestHandler?(presentation, height)
    }
}
