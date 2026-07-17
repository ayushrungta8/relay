import Observation

@MainActor
@Observable
final class RelayNotchPanelState {
    let drafts = RelayPanelDraftStore()
    var presentation: RelayPanelPresentation = .hidden
    var topInset: Double = 0
    @ObservationIgnored
    var presentationRequestHandler:
        ((RelayPanelPresentation) -> Void)?
    @ObservationIgnored
    var contentHeightRequestHandler:
        ((RelayPanelPresentation, Double) -> Void)?
    @ObservationIgnored
    var priorityActivityHandler: ((RelayAutomaticPeekTrigger?) -> Void)?

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

    func requestCollapse() {
        guard drafts.canDismiss else { return }
        requestPresentation(presentation.collapsed)
    }

    func priorityActivityChanged(_ trigger: RelayAutomaticPeekTrigger?) {
        priorityActivityHandler?(trigger)
    }
}
