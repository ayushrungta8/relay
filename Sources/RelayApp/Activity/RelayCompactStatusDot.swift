import RelayCore
import SwiftUI

struct RelayCompactStatusDot: View {
    let state: RelayTaskAttentionState

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isExpanded = false

    var body: some View {
        ZStack {
            Circle()
                .fill(color.opacity(0.25))
                .frame(width: 18, height: 18)
                .scaleEffect(isExpanded ? 1.08 : 0.86)

            Circle()
                .fill(color)
                .frame(width: 7, height: 7)
        }
        .frame(width: 20, height: 20)
        .animation(animation, value: isExpanded)
        .task(id: animates) {
            isExpanded = animates
        }
        .accessibilityHidden(true)
    }

    private var animates: Bool {
        state == .needsInput
            && RelayAccessibilityContract.allowsLoopingStatusMotion(
                reduceMotion: reduceMotion
            )
    }

    private var animation: Animation? {
        guard animates else { return nil }
        return .easeInOut(duration: 1.25).repeatForever(
            autoreverses: true
        )
    }

    private var color: Color {
        switch state {
        case .needsInput: RelayPalette.needsInput
        case .failed: RelayPalette.failed
        case .ready: RelayPalette.ready
        case .running: RelayPalette.running
        case .idle: RelayPalette.idle
        }
    }
}
