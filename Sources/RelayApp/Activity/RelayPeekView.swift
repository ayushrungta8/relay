import SwiftUI

struct RelayPeekView: View {
    let activity: RelayActivityPresentation
    let safeArea: RelayNotchSafeArea
    let expand: () -> Void

    var body: some View {
        Button(action: expand) {
            RelayCompactSummaryLabel(
                activity: activity,
                safeArea: safeArea
            )
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Open Relay activity center")
        .accessibilityValue(activity.compactPrimaryCopy)
    }
}
