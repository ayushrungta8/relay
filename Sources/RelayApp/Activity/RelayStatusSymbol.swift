import RelayCore
import SwiftUI

struct RelayStatusSymbol: View {
    let state: RelayTaskAttentionState

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
