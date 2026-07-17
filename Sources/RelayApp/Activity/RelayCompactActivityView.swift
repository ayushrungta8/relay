import SwiftUI

struct RelayCompactActivityView: View {
    let activity: RelayActivityPresentation
    var voiceActivity: RelayVoiceActivity = .inactive
    let safeArea: RelayNotchSafeArea
    let expand: () -> Void

    var body: some View {
        Button(action: expand) {
            RelayCompactSummaryLabel(
                activity: activity,
                voiceActivity: voiceActivity,
                safeArea: safeArea
            )
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Open Relay activity center")
        .accessibilityValue(
            voiceActivity.isActive
                ? voiceActivity.label
                : activity.compactAccessibilityCopy
        )
        .accessibilityHint("Expands Relay")
    }
}
