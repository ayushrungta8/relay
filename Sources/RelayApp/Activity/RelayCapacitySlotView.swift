import SwiftUI

struct RelayCapacitySlotView: View {
    let window: RelayCapacityPresentation.Window?

    var body: some View {
        if let window {
            RelayCapacityWindowView(window: window)
        } else {
            HStack {
                Text("Usage unavailable")
                Spacer()
                Image(systemName: "eye.slash")
            }
            .font(.callout)
            .foregroundStyle(RelayPalette.secondaryText)
            .padding(.horizontal, 16)
            .accessibilityElement(children: .combine)
        }
    }
}
