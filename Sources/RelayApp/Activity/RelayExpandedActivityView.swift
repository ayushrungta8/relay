import RelayCore
import SwiftUI

struct RelayExpandedActivityView: View {
    let activity: RelayActivityPresentation
    let capacity: RelayCapacityPresentation
    let tokenUsageByThreadID: [String: RelayThreadTokenUsage]
    let pendingInteractions: [RelayPendingInteraction]
    let drafts: RelayPanelDraftStore
    let actions: RelayTaskActions
    @Binding var commandText: String
    let composerPhase: RelayComposerPhase
    let latestResponse: String?
    let connection: RelayConnectionPresentation?
    let safeArea: RelayNotchSafeArea
    let submitCommand: () -> Void
    let retryConnection: () -> Void
    let submitPendingAnswers:
        (String, [String: [String]]) async throws -> Void
    let submitPendingDecision:
        (String, RelayPendingApprovalDecision) async throws -> Void
    let collapse: () -> Void

    @State private var selectedTaskID: String?
    @State private var operationState = RelayTaskOperationState()

    var body: some View {
        VStack(spacing: 0) {
            RelayExpandedHeader(
                summary: activity.expandedHeaderSummaryCopy,
                safeArea: safeArea,
                canOpenInCodex: selectedTask != nil,
                openInCodex: openSelectedTaskInCodex,
                collapse: collapse
            )

            Divider().overlay(RelayPalette.hairline)

            HStack(spacing: 0) {
                RelayTaskRail(
                    tasks: activity.orderedTasks,
                    selectedID: selectedTaskID,
                    select: selectTask
                )
                .frame(width: 232)

                Divider().overlay(RelayPalette.hairline)

                detailColumn
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .frame(maxHeight: .infinity)

            Divider().overlay(RelayPalette.hairline)

            RelayCapacityFooter(presentation: capacity)

            Divider().overlay(RelayPalette.hairline)

            if normalizedLatestResponse != nil {
                answerRegion
                    .frame(height: 36)

                Divider().overlay(RelayPalette.hairline)
            }

            RelayCommandComposerView(
                text: $commandText,
                phase: composerPhase,
                submit: submitCommand
            )
            .frame(height: 50)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .onChange(of: orderedTaskIDs, initial: true) { _, _ in
            selectedTaskID = RelayTaskSelection.resolvedID(
                preferredID: selectedTaskID,
                orderedTasks: activity.orderedTasks
            )
        }
    }

    @ViewBuilder
    private var detailColumn: some View {
        if !drafts.orphanedDrafts.isEmpty {
            ScrollView {
                RelayOrphanedDraftsView(drafts: drafts)
                    .padding(12)
            }
            .scrollIndicators(.never)
        } else {
            VStack(spacing: 0) {
                if let connection, connection.isVisible {
                    RelayConnectionStatusView(
                        presentation: connection,
                        retry: retryConnection
                    )
                    .padding(8)
                }

                if let selectedTask {
                    RelaySelectedTaskView(
                        task: selectedTask,
                        tokenUsage: tokenUsageByThreadID[selectedTask.id],
                        pendingInteractions: pendingInteractions.filter {
                            $0.threadID == selectedTask.id
                        },
                        drafts: drafts,
                        actions: actions,
                        operationState: $operationState,
                        submitPendingAnswers: submitPendingAnswers,
                        submitPendingDecision: submitPendingDecision
                    )
                } else {
                    ContentUnavailableView {
                        Label(
                            "No Codex activity",
                            systemImage: "checkmark.circle"
                        )
                    } description: {
                        Text("Running work and anything that needs you will appear here.")
                    }
                    .foregroundStyle(RelayPalette.secondaryText)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
        }
    }

    @ViewBuilder
    private var answerRegion: some View {
        if let answer = normalizedLatestResponse {
            RelayControllerAnswerView(answer: answer)
        } else {
            Color.clear.accessibilityHidden(true)
        }
    }

    private var orderedTaskIDs: [String] {
        activity.orderedTasks.map(\.id)
    }

    private var selectedTask: RelayTaskActivity? {
        guard let selectedTaskID else { return nil }
        return activity.orderedTasks.first { $0.id == selectedTaskID }
    }

    private var normalizedLatestResponse: String? {
        let answer = latestResponse?.trimmingCharacters(
            in: .whitespacesAndNewlines
        )
        guard let answer, !answer.isEmpty else { return nil }
        return answer
    }

    private func selectTask(_ task: RelayTaskActivity) {
        selectedTaskID = task.id
        Task { await actions.select(task) }
    }

    private func openSelectedTaskInCodex() {
        guard let selectedTask else { return }
        let taskID = selectedTask.id
        operationState.recordError(nil, taskID: taskID)
        Task {
            do {
                try await actions.open(selectedTask)
            } catch {
                operationState.recordError(
                    error.localizedDescription,
                    taskID: taskID
                )
            }
        }
    }

}
