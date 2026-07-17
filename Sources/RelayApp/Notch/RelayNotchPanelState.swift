import Observation

@MainActor
@Observable
final class RelayNotchPanelState {
    let drafts = RelayPanelDraftStore()
    var presentation: RelayPanelPresentation = .hidden
    var notchSafeArea = RelayNotchSafeArea(
        topInset: 0,
        obstructionWidth: 0
    )
    @ObservationIgnored
    var presentationRequestHandler:
        ((RelayPanelPresentation) -> Void)?
    @ObservationIgnored
    var priorityActivityHandler: ((RelayAutomaticPeekTrigger?) -> Void)?

    func requestPresentation(
        _ presentation: RelayPanelPresentation
    ) {
        guard presentation != .hidden || drafts.canDismiss else { return }
        presentationRequestHandler?(presentation)
    }

    func toggleTarget() -> RelayPanelPresentation? {
        let target = presentation.toggled
        guard target != .hidden || drafts.canDismiss else { return nil }
        return target
    }

    func requestCollapse() {
        guard drafts.canDismiss else { return }
        requestPresentation(presentation.collapsed)
    }

    func priorityActivityChanged(_ trigger: RelayAutomaticPeekTrigger?) {
        priorityActivityHandler?(trigger)
    }
}
