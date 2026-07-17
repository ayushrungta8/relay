import SwiftUI

struct RelayCapacityWindowView: View {
    let window: RelayCapacityPresentation.Window

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(window.label)
                    .lineLimit(1)
                Spacer()
                Text("\(window.usedPercent)%")
                    .monospacedDigit()
            }
            .font(.callout)
            .foregroundStyle(RelayPalette.primaryText)

            RelayProgressBar(
                progress: window.progress,
                colors: levelColors
            )
        }
        .padding(.horizontal, 16)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(
            "\(window.label), \(window.usedPercent) percent used, \(window.level.label)"
        )
    }

    private var levelColors: [Color] {
        switch window.level {
        case .standard:
            [RelayPalette.accent, RelayPalette.accentHighlight]
        case .warning:
            [RelayPalette.warning, RelayPalette.accentHighlight]
        case .critical:
            [RelayPalette.critical, RelayPalette.accent]
        }
    }
}
