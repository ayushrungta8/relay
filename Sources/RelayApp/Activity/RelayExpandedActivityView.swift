import RelayCore
import SwiftUI

struct RelayExpandedActivityView: View {
    let activity: RelayActivityPresentation
    let capacity: RelayCapacityPresentation
    let tokenUsageByThreadID: [String: RelayThreadTokenUsage]
    let actions: RelayTaskActions
    @Binding var commandText: String
    let composerPhase: RelayComposerPhase
    let submitCommand: () -> Void
    let collapse: () -> Void
    let contentHeightChanged: (Double) -> Void

    @State private var showsUsageDetail = false
    @State private var headerHeight: Double = 0
    @State private var scrollContentHeight: Double = 0
    @State private var composerHeight: Double = 0

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                Label("Relay", systemImage: "arrow.left.arrow.right")
                    .font(.headline)
                    .foregroundStyle(RelayPalette.primaryText)

                Spacer()

                Text(summaryCopy)
                    .font(.caption)
                    .foregroundStyle(RelayPalette.secondaryText)

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
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .onGeometryChange(for: Double.self) { proxy in
                Double(proxy.size.height)
            } action: { height in
                measuredHeader(height)
            }

            Divider()
                .overlay(RelayPalette.hairline)

            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    if activity.orderedTasks.isEmpty {
                        ContentUnavailableView {
                            Label(
                                "No Codex activity",
                                systemImage: "checkmark.circle"
                            )
                        } description: {
                            Text(
                                "Running work and anything that needs you will appear here."
                            )
                        }
                        .foregroundStyle(RelayPalette.secondaryText)
                        .frame(maxWidth: .infinity, minHeight: 150)
                    } else {
                        TaskSection(
                            title: "Attention",
                            systemImage: "exclamationmark.bubble",
                            tasks: activity.attentionTasks,
                            tokenUsageByThreadID: tokenUsageByThreadID,
                            actions: actions
                        )

                        TaskSection(
                            title: "Running",
                            systemImage: "ellipsis.circle",
                            tasks: activity.runningTasks,
                            tokenUsageByThreadID: tokenUsageByThreadID,
                            actions: actions
                        )

                        TaskSection(
                            title: "Recent",
                            systemImage: "clock",
                            tasks: activity.recentTasks,
                            tokenUsageByThreadID: tokenUsageByThreadID,
                            actions: actions
                        )
                    }

                    Divider()
                        .overlay(RelayPalette.hairline)

                    VStack(spacing: 0) {
                        RelayCapacityStrip(
                            presentation: capacity,
                            isExpanded: showsUsageDetail,
                            toggleDetail: toggleUsageDetail
                        )

                        if showsUsageDetail {
                            RelayUsageDetailView(
                                presentation: capacity
                            )
                        }
                    }
                    .background(
                        RelayPalette.elevatedSurface,
                        in: .rect(cornerRadius: 10)
                    )
                }
                .padding(14)
                .onGeometryChange(for: Double.self) { proxy in
                    Double(proxy.size.height)
                } action: { height in
                    measuredScrollContent(height)
                }
            }
            .scrollIndicators(.never)

            Divider()
                .overlay(RelayPalette.hairline)

            RelayCommandComposerView(
                text: $commandText,
                phase: composerPhase,
                submit: submitCommand
            )
            .background(RelayPalette.elevatedSurface)
            .onGeometryChange(for: Double.self) { proxy in
                Double(proxy.size.height)
            } action: { height in
                measuredComposer(height)
            }
        }
    }

    private var summaryCopy: String {
        activity.expandedSummaryCopy
    }

    private func toggleUsageDetail() {
        showsUsageDetail.toggle()
    }

    private func measuredHeader(_ height: Double) {
        headerHeight = height
        publishContentHeight()
    }

    private func measuredScrollContent(_ height: Double) {
        scrollContentHeight = height
        publishContentHeight()
    }

    private func measuredComposer(_ height: Double) {
        composerHeight = height
        publishContentHeight()
    }

    private func publishContentHeight() {
        guard
            headerHeight > 0,
            scrollContentHeight > 0,
            composerHeight > 0
        else {
            return
        }
        contentHeightChanged(
            headerHeight + scrollContentHeight + composerHeight + 2
        )
    }
}

private extension RelayExpandedActivityView {
    struct TaskSection: View {
        let title: String
        let systemImage: String
        let tasks: [RelayTaskActivity]
        let tokenUsageByThreadID: [String: RelayThreadTokenUsage]
        let actions: RelayTaskActions

        var body: some View {
            if !tasks.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Label(title, systemImage: systemImage)
                        .font(.callout)
                        .bold()
                        .foregroundStyle(RelayPalette.secondaryText)
                        .accessibilityAddTraits(.isHeader)

                    ForEach(tasks) { task in
                        RelayTaskCard(
                            task: task,
                            tokenUsage: tokenUsageByThreadID[task.id],
                            layout: .expanded,
                            actions: actions,
                            primaryAction: {}
                        )
                    }
                }
            }
        }
    }
}
