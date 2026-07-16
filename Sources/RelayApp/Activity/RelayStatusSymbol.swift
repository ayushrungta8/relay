import RelayCore
import SwiftUI

struct RelayStatusSymbol: View {
    let state: RelayTaskAttentionState

    var systemName: String {
        switch state {
        case .needsInput:
            "exclamationmark.bubble.fill"
        case .failed:
            "xmark.octagon.fill"
        case .ready:
            "checkmark.circle.fill"
        case .running:
            "ellipsis.circle.fill"
        case .idle:
            "clock.fill"
        }
    }

    var label: String {
        switch state {
        case .needsInput:
            "Needs input"
        case .failed:
            "Failed"
        case .ready:
            "Ready"
        case .running:
            "Running"
        case .idle:
            "Idle"
        }
    }

    var body: some View {
        Label(label, systemImage: systemName)
            .foregroundStyle(color)
            .accessibilityLabel(label)
    }

    private var color: Color {
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
}
