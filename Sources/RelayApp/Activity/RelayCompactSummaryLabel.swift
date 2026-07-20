import SwiftUI

struct RelayCompactSummaryLabel: View {
    let activity: RelayActivityPresentation
    var voiceActivity: RelayVoiceActivity = .inactive
    let safeArea: RelayNotchSafeArea

    var body: some View {
        Group {
            if safeArea.topInset > 0 {
                HStack(spacing: 0) {
                    primaryStatus
                        .frame(maxWidth: .infinity, alignment: .leading)

                    Color.clear
                        .frame(width: safeArea.contentClearanceWidth)
                        .accessibilityHidden(true)

                    chevron
                        .frame(maxWidth: .infinity, alignment: .trailing)
                }
            } else {
                HStack(spacing: 0) {
                    primaryStatus
                        .frame(maxWidth: .infinity, alignment: .leading)

                    Spacer(minLength: 12)

                    trailingStatus
                        .frame(maxWidth: .infinity, alignment: .trailing)
                }
            }
        }
        .padding(.horizontal, 14)
        .frame(height: 42)
        .contentShape(.rect)
    }

    private var primaryStatus: some View {
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
    }

    private var trailingStatus: some View {
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

            chevron
        }
    }

    private var chevron: some View {
        Image(systemName: "chevron.down")
            .font(.caption)
            .foregroundStyle(RelayPalette.tertiaryText)
            .accessibilityHidden(true)
    }

    private var primaryCopy: String {
        voiceActivity.isActive
            ? voiceActivity.label
            : activity.compactPrimaryCopy
    }
}
