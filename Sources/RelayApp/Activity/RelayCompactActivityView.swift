import RelayCore
import SwiftUI

struct RelayCompactActivityView: View {
    let activity: RelayActivityPresentation
    let capacity: RelayCapacityPresentation
    let tokenUsageByThreadID: [String: RelayThreadTokenUsage]
    let actions: RelayTaskActions
    let expand: () -> Void

    var body: some View {
        VStack(spacing: 10) {
            Button(action: expand) {
                HStack(spacing: 9) {
                    Image(systemName: "arrow.left.arrow.right")
                        .foregroundStyle(RelayPalette.ready)
                        .accessibilityHidden(true)

                    Text(activity.peekCopy)
                        .font(.callout)
                        .bold()
                        .foregroundStyle(RelayPalette.primaryText)
                        .lineLimit(1)

                    Spacer(minLength: 12)

                    Text("Open activity center")
                        .font(.caption)
                        .foregroundStyle(RelayPalette.secondaryText)

                    Image(systemName: "chevron.down")
                        .font(.caption)
                        .foregroundStyle(RelayPalette.tertiaryText)
                        .accessibilityHidden(true)
                }
                .contentShape(.rect)
            }
            .buttonStyle(.plain)
            .accessibilityHint("Expands Relay")

            if activity.orderedTasks.isEmpty {
                Label("No active Codex tasks", systemImage: "checkmark.circle")
                    .font(.body)
                    .foregroundStyle(RelayPalette.secondaryText)
                    .frame(maxWidth: .infinity, minHeight: 62)
            } else {
                ScrollView(.horizontal) {
                    LazyHStack(spacing: 8) {
                        ForEach(activity.orderedTasks.prefix(8)) { task in
                            RelayTaskCard(
                                task: task,
                                tokenUsage:
                                    tokenUsageByThreadID[task.id],
                                layout: .compact,
                                actions: actions,
                                primaryAction: expand
                            )
                        }
                    }
                }
                .scrollIndicators(.hidden)
            }

            RelayCapacityStrip(
                presentation: capacity,
                isExpanded: false
            )
        }
        .padding(.horizontal, 14)
        .padding(.bottom, 12)
    }
}
