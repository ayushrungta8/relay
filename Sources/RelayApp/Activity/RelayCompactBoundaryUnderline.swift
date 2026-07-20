import SwiftUI

struct RelayCompactBoundaryUnderline: View {
    var body: some View {
        continuousBoundary
            .padding(.horizontal, 15)
            .padding(.bottom, 1)
            .allowsHitTesting(false)
            .accessibilityHidden(true)
    }

    private var continuousBoundary: some View {
        Capsule()
            .fill(
                LinearGradient(
                    stops: [
                        .init(color: Color.white.opacity(0.18), location: 0),
                        .init(
                            color: RelayPalette.accent.opacity(0.62),
                            location: 0.34
                        ),
                        .init(
                            color: RelayPalette.accentHighlight.opacity(0.52),
                            location: 0.66
                        ),
                        .init(color: Color.white.opacity(0.18), location: 1),
                    ],
                    startPoint: .leading,
                    endPoint: .trailing
                )
            )
            .frame(height: 1.5)
    }
}
