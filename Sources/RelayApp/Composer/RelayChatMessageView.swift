import SwiftUI

struct RelayChatMessageView: View {
    let message: RelayChatMessage

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            Label(speaker, systemImage: systemImage)
                .font(.caption.weight(.semibold))
                .foregroundStyle(labelColor)

            Text(message.text)
                .font(.body)
                .foregroundStyle(RelayPalette.primaryText)
                .textSelection(.enabled)
                .lineSpacing(3)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 12)
        .background(backgroundColor)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(speaker): \(message.text)")
    }

    private var speaker: String {
        switch message.role {
        case .user:
            "You"
        case .relay:
            "Relay"
        }
    }

    private var systemImage: String {
        switch message.role {
        case .user:
            "person.fill"
        case .relay:
            "sparkles"
        }
    }

    private var labelColor: Color {
        switch message.role {
        case .user:
            RelayPalette.accent
        case .relay:
            RelayPalette.secondaryText
        }
    }

    private var backgroundColor: Color {
        switch message.role {
        case .user:
            RelayPalette.fieldSurface.opacity(0.5)
        case .relay:
            .clear
        }
    }
}
