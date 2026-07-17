import SwiftUI

struct RelayCompactSummaryLabel: View {
    let activity: RelayActivityPresentation
    let safeArea: RelayNotchSafeArea

    var body: some View {
        HStack(spacing: 0) {
            HStack(spacing: 8) {
                RelayCompactStatusDot(state: activity.compactState)

                Text(activity.compactPrimaryCopy)
                    .font(.body)
                    .bold()
                    .foregroundStyle(RelayPalette.primaryText)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Spacer(minLength: 12)

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
        .frame(height: 42)
        .padding(.top, max(0, safeArea.topInset))
        .contentShape(.rect)
    }
}
