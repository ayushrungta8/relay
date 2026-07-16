import Observation

@MainActor
@Observable
final class RelayNotchPanelState {
    var presentation: RelayPanelPresentation = .hidden
}
