import SwiftUI

struct RelayUsageDetailView: View {
    let presentation: RelayCapacityPresentation

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if presentation.windows.isEmpty {
                Label(
                    "Codex did not provide account usage.",
                    systemImage: "eye.slash"
                )
                .font(.callout)
                .foregroundStyle(RelayPalette.secondaryText)
            } else {
                ForEach(presentation.windows) { window in
                    WindowDetail(window: window)

                    if window.id != presentation.windows.last?.id {
                        Divider()
                            .overlay(RelayPalette.hairline)
                    }
                }
            }

            Divider()
                .overlay(RelayPalette.hairline)

            Label(
                presentation.resetCreditsCopy,
                systemImage: "arrow.counterclockwise.circle"
            )
            .font(.callout)
            .foregroundStyle(RelayPalette.secondaryText)

            if let credits = presentation.resetCredits, !credits.isEmpty {
                ForEach(credits, id: \.id) { credit in
                    VStack(alignment: .leading, spacing: 3) {
                        Text(creditTitle(credit.title))
                            .font(.callout)
                            .bold()
                            .foregroundStyle(RelayPalette.primaryText)

                        if let expiresAt = credit.expiresAt {
                            LabeledContent("Expires") {
                                Text(
                                    RelayCapacityPresentation.timestampLabel(
                                        for: Date(
                                            timeIntervalSince1970:
                                                TimeInterval(expiresAt)
                                        )
                                    )
                                )
                                .monospacedDigit()
                            }
                            .font(.caption)
                            .foregroundStyle(RelayPalette.secondaryText)
                        } else {
                            Text("Expiry unavailable")
                                .font(.caption)
                                .foregroundStyle(RelayPalette.secondaryText)
                        }
                    }
                }
            }
        }
        .padding(.horizontal, 12)
        .padding(.bottom, 12)
    }

    private func creditTitle(_ title: String?) -> String {
        let title = title?.trimmingCharacters(in: .whitespacesAndNewlines)
        if let title, !title.isEmpty {
            return title
        }
        return "Reset credit"
    }
}

private extension RelayUsageDetailView {
    struct WindowDetail: View {
        let window: RelayCapacityPresentation.Window

        var body: some View {
            VStack(alignment: .leading, spacing: 7) {
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(window.label)
                            .font(.callout)
                            .bold()
                            .foregroundStyle(RelayPalette.primaryText)

                        HStack(spacing: 5) {
                            Image(systemName: levelSymbol)
                                .foregroundStyle(levelColor)
                                .accessibilityHidden(true)

                            Text(window.level.label)
                                .foregroundStyle(
                                    RelayPalette.secondaryText
                                )
                        }
                        .font(.caption)
                    }

                    Spacer()

                    Text("\(window.usedPercent)%")
                        .font(.callout)
                        .monospacedDigit()
                        .foregroundStyle(RelayPalette.primaryText)
                }

                ProgressView(value: window.progress)
                    .progressViewStyle(.linear)
                    .tint(levelColor)
                    .accessibilityLabel(window.label)
                    .accessibilityValue(
                        "\(window.usedPercent) percent used, \(window.level.label)"
                    )

                if let resetDate = window.resetDate {
                    LabeledContent("Resets") {
                        Text(
                            RelayCapacityPresentation.timestampLabel(
                                for: resetDate
                            )
                        )
                        .monospacedDigit()
                    }
                    .font(.caption)
                    .foregroundStyle(RelayPalette.secondaryText)
                } else {
                    Text("Reset time unavailable")
                        .font(.caption)
                        .foregroundStyle(RelayPalette.secondaryText)
                }
            }
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
