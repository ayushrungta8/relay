import SwiftUI

struct RelayBrandSymbol: View {
    var body: some View {
        Image(systemName: "antenna.radiowaves.left.and.right")
            .font(.callout)
            .foregroundStyle(RelayPalette.primaryText)
            .frame(width: 26, height: 26)
            .background(
                LinearGradient(
                    colors: [
                        RelayPalette.accent,
                        RelayPalette.accentPressed,
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                ),
                in: .circle
            )
            .shadow(
                color: RelayPalette.accent.opacity(0.34),
                radius: 6
            )
            .accessibilityHidden(true)
    }
}
