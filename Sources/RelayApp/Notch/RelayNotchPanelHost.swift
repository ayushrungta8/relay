import SwiftUI

struct RelayNotchPanelHost: View {
    let model: RelayAppModel
    let state: RelayNotchPanelState

    var body: some View {
        ZStack {
            UnevenRoundedRectangle(
                topLeadingRadius: 2,
                bottomLeadingRadius: 16,
                bottomTrailingRadius: 16,
                topTrailingRadius: 2
            )
            .fill(.black)

            Label("Relay", systemImage: "arrow.left.arrow.right")
                .font(.headline)
                .foregroundStyle(.white)
                .opacity(state.presentation == .hidden ? 0 : 1)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilityLabel)
    }

    private var accessibilityLabel: String {
        switch state.presentation {
        case .hidden:
            "Relay hidden"
        case .peek:
            "Relay status"
        case .compact:
            "Relay activity center"
        case .expanded:
            "Relay expanded activity center"
        }
    }
}
