import SwiftUI

struct RelayExpandedHeader: View {
    let summary: String
    let safeArea: RelayNotchSafeArea
    let collapse: () -> Void

    var body: some View {
        HStack(spacing: 0) {
            Label("Relay", systemImage: "arrow.left.arrow.right")
                .font(.headline)
                .foregroundStyle(RelayPalette.primaryText)
                .frame(maxWidth: .infinity, alignment: .leading)

            Color.clear
                .frame(width: safeArea.contentClearanceWidth)
                .accessibilityHidden(true)

            HStack(spacing: 10) {
                Text(summary)
                    .font(.caption)
                    .foregroundStyle(RelayPalette.secondaryText)
                    .lineLimit(1)

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
        .frame(height: max(42, safeArea.topInset))
    }
}
