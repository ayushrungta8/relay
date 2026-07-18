import SwiftUI

struct RelayVoiceSetupView: View {
    let presentation: RelayVoiceSetupPresentation
    let isResolving: Bool
    let performPrimaryAction: () -> Void
    let dismiss: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: "waveform.badge.mic")
                    .font(.title2)
                    .foregroundStyle(RelayPalette.accent)
                    .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: 7) {
                    Text(presentation.title)
                        .font(.headline)
                        .foregroundStyle(RelayPalette.primaryText)

                    Text(presentation.message)
                        .font(.body)
                        .foregroundStyle(RelayPalette.secondaryText)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer(minLength: 12)

                Button("Dismiss", systemImage: "xmark", action: dismiss)
                    .labelStyle(.iconOnly)
                    .buttonStyle(.plain)
                    .foregroundStyle(RelayPalette.tertiaryText)
                    .frame(width: 28, height: 28)
            }

            if let diagnostic = presentation.diagnostic {
                Text(diagnostic)
                    .font(.caption.monospaced())
                    .foregroundStyle(RelayPalette.tertiaryText)
                    .textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if let actionTitle = presentation.primaryActionTitle {
                HStack {
                    Spacer()

                    Button(action: performPrimaryAction) {
                        HStack(spacing: 8) {
                            if isResolving {
                                ProgressView()
                                    .controlSize(.small)
                            }
                            Text(actionTitle)
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(isResolving)
                }
            }
        }
        .padding(20)
        .frame(maxWidth: 460)
        .background(
            RelayPalette.elevatedSurface,
            in: .rect(cornerRadius: 14)
        )
        .overlay {
            RoundedRectangle(cornerRadius: 14)
                .stroke(RelayPalette.hairline, lineWidth: 1)
                .allowsHitTesting(false)
        }
        .tint(RelayPalette.accent)
        .accessibilityElement(children: .contain)
    }
}
