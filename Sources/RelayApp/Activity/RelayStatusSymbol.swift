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
        Label {
            Text(label)
                .foregroundStyle(labelColor)
        } icon: {
            Image(systemName: systemName)
                .foregroundStyle(iconColor)
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
}
