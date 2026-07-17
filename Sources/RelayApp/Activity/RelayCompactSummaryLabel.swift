import SwiftUI

struct RelayCompactSummaryLabel: View {
    let activity: RelayActivityPresentation
    var voiceActivity: RelayVoiceActivity = .inactive
    let safeArea: RelayNotchSafeArea

    var body: some View {
        HStack(spacing: 0) {
            HStack(spacing: 8) {
                if voiceActivity.isActive {
                    RelayVoiceActivityDot(activity: voiceActivity)
                } else {
                    RelayCompactStatusDot(state: activity.compactState)
                }

                Text(primaryCopy)
                    .font(.body)
                    .bold()
                    .foregroundStyle(RelayPalette.primaryText)
                    .lineLimit(1)
                    .contentTransition(.opacity)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Spacer(minLength: 12)

            HStack(spacing: 7) {
                if !voiceActivity.isActive {
                    if activity.runningTasks.isEmpty == false {
                        RelayRunningGlyph()
                    }

                    if let secondary = activity.compactSecondaryCopy {
                        Text(secondary)
                            .font(.caption)
                            .foregroundStyle(RelayPalette.secondaryText)
                            .lineLimit(1)
                    }
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

    private var primaryCopy: String {
        voiceActivity.isActive
            ? voiceActivity.label
            : activity.compactPrimaryCopy
    }
}
