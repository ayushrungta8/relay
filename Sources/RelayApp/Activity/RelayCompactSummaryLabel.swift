import SwiftUI

struct RelayCompactSummaryLabel: View {
    let activity: RelayActivityPresentation
    let safeArea: RelayNotchSafeArea

    var body: some View {
        HStack(spacing: 0) {
            HStack(spacing: 8) {
                RelayStatusSymbol(
                    state: activity.compactState,
                    showsAttentionHalo: true
                )
                .labelStyle(.iconOnly)

                Text(activity.compactPrimaryCopy)
                    .font(.callout)
                    .bold()
                    .foregroundStyle(RelayPalette.primaryText)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Color.clear
                .frame(width: safeArea.contentClearanceWidth)
                .accessibilityHidden(true)

            HStack(spacing: 7) {
                if activity.runningTasks.isEmpty == false {
                    RelayRunningGlyph()
                }

                if let secondary = activity.compactSecondaryCopy {
                    Text(secondary)
                        .font(.caption)
                        .foregroundStyle(RelayPalette.secondaryText)
                        .lineLimit(1)
                }

                Image(systemName: "chevron.down")
                    .font(.caption)
                    .foregroundStyle(RelayPalette.tertiaryText)
                    .accessibilityHidden(true)
            }
            .frame(maxWidth: .infinity, alignment: .trailing)
        }
        .padding(.horizontal, 14)
        .frame(minHeight: max(42, safeArea.topInset))
        .contentShape(.rect)
    }
}
