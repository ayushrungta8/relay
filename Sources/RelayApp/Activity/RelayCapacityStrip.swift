import SwiftUI

struct RelayCapacityStrip: View {
    let presentation: RelayCapacityPresentation
    let isExpanded: Bool
    var toggleDetail: (() -> Void)?

    var body: some View {
        Group {
            if let toggleDetail {
                Button(action: toggleDetail) {
                    stripContent
                        .contentShape(.rect)
                }
                .buttonStyle(.plain)
                .accessibilityHint(
                    isExpanded
                        ? "Hides usage and reset details"
                        : "Shows usage and reset details"
                )
            } else {
                stripContent
            }
        }
        .accessibilityElement(children: .contain)
    }

    private var stripContent: some View {
        HStack(spacing: 10) {
            Label(
                presentation.title,
                systemImage: "gauge.with.dots.needle.50percent"
            )
            .font(.caption)
            .bold()
            .foregroundStyle(RelayPalette.secondaryText)
            .lineLimit(1)

            Spacer(minLength: 4)

            if presentation.windows.isEmpty {
                Label(
                    presentation.availabilityCopy,
                    systemImage: "eye.slash"
                )
                .font(.caption)
                .foregroundStyle(RelayPalette.secondaryText)
            } else {
                ForEach(presentation.windows) { window in
                    WindowValue(window: window)
                }
            }

            if toggleDetail != nil {
                Image(
                    systemName: isExpanded
                        ? "chevron.up"
                        : "chevron.down"
                )
                .font(.caption)
                .foregroundStyle(RelayPalette.tertiaryText)
                .accessibilityHidden(true)
            }
        }
        .padding(.horizontal, 12)
        .frame(height: 32)
    }
}

private extension RelayCapacityStrip {
    struct WindowValue: View {
        let window: RelayCapacityPresentation.Window

        var body: some View {
            HStack(spacing: 5) {
                Image(systemName: levelSymbol)
                    .foregroundStyle(levelColor)
                    .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: 1) {
                    Text(window.label)
                        .foregroundStyle(RelayPalette.secondaryText)
                        .lineLimit(1)

                    Text(window.level.label)
                        .foregroundStyle(RelayPalette.primaryText)
                        .lineLimit(1)
                }
                .font(.caption)

                Text("\(window.usedPercent)%")
                    .font(.callout)
                    .monospacedDigit()
                    .foregroundStyle(RelayPalette.primaryText)
            }
            .accessibilityElement(children: .combine)
            .accessibilityLabel(
                "\(window.label), \(window.usedPercent) percent used, \(window.level.label)"
            )
        }

        private var levelColor: Color {
            switch window.level {
            case .standard:
                RelayPalette.ready
            case .warning:
                RelayPalette.warning
            case .critical:
                RelayPalette.critical
            }
        }

        private var levelSymbol: String {
            switch window.level {
            case .standard:
                "circle.fill"
            case .warning:
                "exclamationmark.triangle.fill"
            case .critical:
                "exclamationmark.octagon.fill"
            }
        }

    }
}
