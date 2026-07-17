import SwiftUI

struct RelayProgressBar: View {
    let progress: Double
    let colors: [Color]

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(RelayPalette.elevatedSurface)

                Capsule()
                    .fill(
                        LinearGradient(
                            colors: colors,
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .frame(
                        width: geometry.size.width * clampedProgress
                    )
            }
        }
        .frame(height: 5)
        .animation(
            reduceMotion
                ? .linear(duration: 0.01)
                : .easeOut(duration: 0.22),
            value: clampedProgress
        )
        .accessibilityHidden(true)
    }

    private var clampedProgress: Double {
        min(max(progress, 0), 1)
    }
}
