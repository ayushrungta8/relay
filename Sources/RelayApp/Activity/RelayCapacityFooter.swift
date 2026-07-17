import AppKit
import SwiftUI

struct RelayCapacityFooter: View {
    let presentation: RelayCapacityPresentation
    let openUsage: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            RelayCapacityStrip(presentation: presentation)
                .frame(height: 51)

            Divider().overlay(RelayPalette.hairline)

            resetSummary
                .frame(height: 31)
        }
        .background(RelayPalette.railSurface)
    }

    private var resetSummary: some View {
        Button(action: openUsage) {
            HStack(spacing: 8) {
                Label(resetTimeCopy, systemImage: "clock.arrow.circlepath")
                    .lineLimit(1)

                Text("·")
                    .accessibilityHidden(true)

                Text(presentation.resetCreditsCopy)
                    .lineLimit(1)

                Spacer(minLength: 8)

                Image(systemName: "chevron.right")
                    .font(.caption2.weight(.semibold))
                    .accessibilityHidden(true)
            }
            .font(.caption)
            .foregroundStyle(RelayPalette.secondaryText)
            .padding(.horizontal, 16)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .onContinuousHover { phase in
            switch phase {
            case .active:
                NSCursor.pointingHand.set()
            case .ended:
                NSCursor.arrow.set()
            }
        }
        .accessibilityLabel(
            "\(resetTimeCopy). \(presentation.resetCreditsCopy)"
        )
        .accessibilityHint("Opens the usage section")
    }

    private var resetTimeCopy: String {
        guard let resetDate = presentation.nextResetDate else {
            return "Reset time unavailable"
        }
        return "Resets \(RelayCapacityPresentation.timestampLabel(for: resetDate))"
    }
}
