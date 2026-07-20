import SwiftUI

struct RelayExpandedHeader: View {
    static let height: CGFloat = 46

    let summary: String
    let safeArea: RelayNotchSafeArea
    let canOpenInCodex: Bool
    let openInCodex: () -> Void
    let collapse: () -> Void

    var body: some View {
        HStack(spacing: 0) {
            HStack(spacing: 9) {
                RelayBrandSymbol()

                Text("Relay")
                    .font(.headline)
                    .foregroundStyle(RelayPalette.primaryText)

                Text(summary)
                    .font(.callout)
                    .foregroundStyle(RelayPalette.secondaryText)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Color.clear
                .frame(width: safeArea.contentClearanceWidth)
                .accessibilityHidden(true)

            HStack(spacing: 10) {
                Button(
                    "Open in Codex",
                    action: openInCodex
                )
                .buttonStyle(.plain)
                .foregroundStyle(RelayPalette.secondaryText)
                .disabled(!canOpenInCodex)
                .help("Open selected task in Codex")

                Button(
                    "Collapse activity center",
                    systemImage: "chevron.up",
                    action: collapse
                )
                .labelStyle(.iconOnly)
                .buttonStyle(.plain)
                .foregroundStyle(RelayPalette.secondaryText)
                .help("Collapse Relay")
            }
            .frame(maxWidth: .infinity, alignment: .trailing)
        }
        .padding(.horizontal, 16)
        .frame(height: Self.height)
    }
}
