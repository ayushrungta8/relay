import SwiftUI

struct RelayRunningGlyph: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isExpanded = false

    var body: some View {
        HStack(alignment: .center, spacing: 2) {
            ForEach(0..<3, id: \.self) { index in
                Capsule()
                    .fill(RelayPalette.running)
                    .frame(width: 2, height: 10)
                    .scaleEffect(
                        y: isExpanded
                            ? [0.46, 1, 0.68][index]
                            : [0.86, 0.42, 0.62][index],
                        anchor: .center
                    )
            }
        }
        .frame(width: 10, height: 12)
        .animation(runningAnimation, value: isExpanded)
        .task(id: allowsLoopingMotion) {
            isExpanded = allowsLoopingMotion
        }
        .accessibilityHidden(true)
    }

    private var allowsLoopingMotion: Bool {
        RelayAccessibilityContract.allowsLoopingStatusMotion(
            reduceMotion: reduceMotion
        )
    }

    private var runningAnimation: Animation? {
        guard allowsLoopingMotion else { return nil }
        return .easeInOut(duration: 0.58).repeatForever(
            autoreverses: true
        )
    }
}
