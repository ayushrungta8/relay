import RelayCore
import SwiftUI

struct RelayAmbientLightView: View {
    let state: RelayTaskAttentionState
    let isExpanded: Bool

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isBreathing = false

    var body: some View {
        ZStack {
            RadialGradient(
                colors: [primaryColor.opacity(primaryOpacity), .clear],
                center: .topLeading,
                startRadius: 0,
                endRadius: isExpanded ? 330 : 180
            )
            .scaleEffect(isBreathing ? 1.05 : 0.96, anchor: .topLeading)

            if isExpanded {
                RadialGradient(
                    colors: [secondaryColor.opacity(0.075), .clear],
                    center: .bottomTrailing,
                    startRadius: 0,
                    endRadius: 270
                )
                .scaleEffect(
                    isBreathing ? 0.97 : 1.04,
                    anchor: .bottomTrailing
                )
            }
        }
        .opacity(isBreathing || reduceMotion ? 1 : 0.82)
        .animation(breathingAnimation, value: isBreathing)
        .task(id: animationIdentity) {
            isBreathing = allowsMotion
        }
        .accessibilityHidden(true)
        .allowsHitTesting(false)
    }

    private var primaryColor: Color {
        switch state {
        case .needsInput: RelayPalette.needsInput
        case .failed: RelayPalette.failed
        case .ready: RelayPalette.ready
        case .running: RelayPalette.running
        case .idle: RelayPalette.accent
        }
    }

    private var secondaryColor: Color {
        state == .ready ? RelayPalette.ready : RelayPalette.accentHighlight
    }

    private var primaryOpacity: Double {
        switch state {
        case .needsInput, .failed: 0.15
        case .running: 0.11
        case .ready: 0.095
        case .idle: 0.06
        }
    }

    private var allowsMotion: Bool {
        state != .idle
            && RelayAccessibilityContract.allowsLoopingStatusMotion(
                reduceMotion: reduceMotion
            )
    }

    private var animationIdentity: String {
        "\(state)-\(isExpanded)-\(allowsMotion)"
    }

    private var breathingAnimation: Animation? {
        guard allowsMotion else { return nil }
        return .easeInOut(duration: 2.8).repeatForever(
            autoreverses: true
        )
    }
}
