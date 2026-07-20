import RelayCore
import SwiftUI

struct RelayExpandedActivityView: View {
    let activity: RelayActivityPresentation
    let capacity: RelayCapacityPresentation
    let tokenUsageByThreadID: [String: RelayThreadTokenUsage]
    let pendingInteractions: [RelayPendingInteraction]
    let drafts: RelayPanelDraftStore
    let actions: RelayTaskActions
    let usageActions: RelayUsageActions
    let autoApplyResetCredits: Bool
    let settings: RelaySettingsStore
    let settingsErrorMessage: String?
    @Binding var selectedSection: RelayExpandedSection
    @Binding var commandText: String
    let composerPhase: RelayComposerPhase
    let chatMessages: [RelayChatMessage]
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
    private let updateController = RelayUpdateController.shared

    var body: some View {
        VStack(spacing: 0) {
            RelayExpandedHeader(
                summary: activity.expandedHeaderSummaryCopy,
                safeArea: safeArea,
                canOpenInCodex: selectedTask != nil,
                openInCodex: openSelectedTaskInCodex,
                collapse: collapse
            )

            if updateController.presentation.isVisible {
                Divider().overlay(RelayPalette.hairline)

                RelayUpdateBanner(
                    presentation: updateController.presentation,
                    canInstall: canInstallUpdate,
                    install: updateController.installAvailableUpdate,
                    deferUpdate: updateController.deferAvailableUpdate,
                    retry: updateController.checkForUpdates,
                    dismiss: updateController.dismissStatus
                )
            }

            Divider().overlay(RelayPalette.hairline)

            RelayExpandedSectionPicker(selection: $selectedSection)

            Divider().overlay(RelayPalette.hairline)

            switch selectedSection {
            case .activity:
                activityRegion
            case .chat:
                RelayChatView(messages: chatMessages)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)

                Divider().overlay(RelayPalette.hairline)

                RelayCommandComposerView(
                    text: $commandText,
                    phase: composerPhase,
                    submit: submitCommand
                )
                .frame(height: 50)
            case .usage:
                RelayUsageSectionView(
                    capacity: capacity,
                    autoApplyResetCredits: autoApplyResetCredits,
                    actions: usageActions
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            case .settings:
                RelaySettingsView(
                    settings: settings,
                    updateController: updateController,
                    shortcutError: settingsErrorMessage
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .onChange(of: orderedTaskIDs, initial: true) { _, _ in
            guard let selectedTaskID else { return }
            if !orderedTaskIDs.contains(selectedTaskID) {
                self.selectedTaskID = nil
            }
        }
    }

    private var activityRegion: some View {
        VStack(spacing: 0) {
            taskList
                .frame(maxHeight: .infinity)

            Divider().overlay(RelayPalette.hairline)

            RelayCapacityFooter(
                presentation: capacity,
                openUsage: { selectedSection = .usage }
            )
        }
    }

    private var taskList: some View {
        VStack(spacing: 0) {
            RelayFullWidthTaskListHeader(taskCount: activity.orderedTasks.count)

            Divider().overlay(RelayPalette.hairline)

            if activity.orderedTasks.isEmpty {
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
            } else {
                ScrollView {
                    LazyVStack(spacing: 0) {
                        if let connection, connection.isVisible {
                            RelayConnectionStatusView(
                                presentation: connection,
                                retry: retryConnection
                            )
                            .padding(10)
                        }

                        if !drafts.orphanedDrafts.isEmpty {
                            RelayOrphanedDraftsView(drafts: drafts)
                                .padding(10)
                        }

                        ForEach(activity.orderedTasks) { task in
                            RelayFullWidthTaskRow(
                                task: task,
                                tokenUsage: tokenUsageByThreadID[task.id],
                                isExpanded: task.id == selectedTaskID,
                                select: { selectTask(task) }
                            )

                            if task.id == selectedTaskID {
                                RelaySelectedTaskView(
                                    task: task,
                                    pendingInteractions: pendingInteractions.filter {
                                        $0.threadID == task.id
                                    },
                                    drafts: drafts,
                                    actions: actions,
                                    operationState: $operationState,
                                    submitPendingAnswers: submitPendingAnswers,
                                    submitPendingDecision: submitPendingDecision
                                )
                            }

                            if task.id != activity.orderedTasks.last?.id {
                                Divider()
                                    .overlay(RelayPalette.hairline)
                                    .padding(.leading, 50)
                            }
                        }
                    }
                }
                .scrollIndicators(.never)
                .background(RelayPalette.detailSurface)
            }
        }
        .accessibilityLabel("Codex tasks")
    }

    private var orderedTaskIDs: [String] {
        activity.orderedTasks.map(\.id)
    }

    private var selectedTask: RelayTaskActivity? {
        guard let selectedTaskID else { return nil }
        return activity.orderedTasks.first { $0.id == selectedTaskID }
    }

    private var canInstallUpdate: Bool {
        let hasCommandDraft = !commandText.trimmingCharacters(
            in: .whitespacesAndNewlines
        ).isEmpty
        let controllerIsBusy: Bool = switch composerPhase {
        case .listening, .sending: true
        case .idle, .failed: false
        }
        return drafts.canDismiss && !hasCommandDraft && !controllerIsBusy
    }

    private func selectTask(_ task: RelayTaskActivity) {
        if selectedTaskID == task.id {
            selectedTaskID = nil
        } else {
            selectedTaskID = task.id
            Task { await actions.select(task) }
        }
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
