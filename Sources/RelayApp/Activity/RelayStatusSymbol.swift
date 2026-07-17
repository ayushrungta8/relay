import RelayCore
import SwiftUI

struct RelayStatusSymbol: View {
    let state: RelayTaskAttentionState
    let showsAttentionHalo: Bool

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var haloExpanded = false

    init(state: RelayTaskAttentionState) {
        self.state = state
        showsAttentionHalo = false
    }

    init(
        state: RelayTaskAttentionState,
        showsAttentionHalo: Bool
    ) {
        self.state = state
        self.showsAttentionHalo = showsAttentionHalo
    }

    var systemName: String {
        RelayAccessibilityContract.status(for: state).systemImage
    }

    var label: String {
        RelayAccessibilityContract.status(for: state).label
    }

    var body: some View {
        Label {
            Text(label)
                .foregroundStyle(labelColor)
        } icon: {
            ZStack {
                Circle()
                    .fill(RelayPalette.needsInput)
                    .frame(width: 14, height: 14)
                    .scaleEffect(haloExpanded ? 1.45 : 0.82)
                    .opacity(attentionHaloOpacity)
                    .accessibilityHidden(true)

                Image(systemName: systemName)
                    .foregroundStyle(iconColor)
            }
            .animation(attentionHaloAnimation, value: haloExpanded)
            .task(id: animatesAttentionHalo) {
                haloExpanded = animatesAttentionHalo
            }
        }
            .accessibilityLabel(label)
    }

    var iconColor: Color {
        switch state {
        case .needsInput:
            RelayPalette.needsInput
        case .failed:
            RelayPalette.failed
        case .ready:
            RelayPalette.ready
        case .running:
            RelayPalette.running
        case .idle:
            RelayPalette.idle
        }
    }

    var labelColor: Color {
        RelayPalette.primaryText
    }

    private var animatesAttentionHalo: Bool {
        showsAttentionHalo
            && state == .needsInput
            && RelayAccessibilityContract.allowsLoopingStatusMotion(
                reduceMotion: reduceMotion
            )
    }

    private var attentionHaloOpacity: Double {
        guard showsAttentionHalo, state == .needsInput else { return 0 }
        guard !reduceMotion else { return 0.16 }
        return haloExpanded ? 0.04 : 0.24
    }

    private var attentionHaloAnimation: Animation? {
        guard animatesAttentionHalo else { return nil }
        return .easeInOut(duration: 1.25).repeatForever(
            autoreverses: true
        )
    }
}
