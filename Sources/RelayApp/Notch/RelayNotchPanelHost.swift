import AppKit
import RelayCore
import SwiftUI

struct RelayNotchPanelHost: View {
    let model: RelayAppModel
    let state: RelayNotchPanelState

    var body: some View {
        @Bindable var model = model

        RelayNotchRootView(
            presentation: state.presentation,
            activity: activityPresentation,
            capacity: capacityPresentation,
            tokenUsageByThreadID:
                model.activityStore?.tokenUsageByThreadID ?? [:],
            pendingInteractions: model.pendingInteractions,
            drafts: state.drafts,
            actions: taskActions,
            commandText: $model.commandText,
            composerPhase: model.composerPhase,
            latestResponse: model.latestResponse,
            connection: connectionPresentation,
            safeArea: state.notchSafeArea,
            submitCommand: submitCommand,
            retryConnection: retryConnection,
            submitPendingAnswers: submitPendingAnswers,
            submitPendingDecision: submitPendingDecision,
            requestPresentation: state.requestPresentation,
            pointerHoverChanged: state.pointerHoverChanged,
            priorityActivityChanged: state.priorityActivityChanged
        )
    }

    private var activityPresentation: RelayActivityPresentation {
        if let store = model.activityStore {
            return RelayActivityPresentation(
                attentionTasks: store.attentionTasks,
                runningTasks: store.runningTasks,
                recentTasks: store.recentTasks
            )
        }
        return RelayActivityPresentation(
            tasks: model.threads.map { RelayTaskActivity(thread: $0) }
        )
    }

    private var capacityPresentation: RelayCapacityPresentation {
        RelayCapacityPresentation(snapshot: model.activityStore?.usage)
    }

    private var connectionPresentation: RelayConnectionPresentation? {
        guard let state = model.activityStore?.connectionState else {
            return nil
        }
        return RelayConnectionPresentation(state: state)
    }

    private var taskActions: RelayTaskActions {
        RelayTaskActions(
            select: select,
            open: open,
            markRead: markRead,
            send: send,
            interrupt: interrupt
        )
    }

    private func select(_ task: RelayTaskActivity) async {
        await model.selectTask(threadID: task.id)
    }

    private func submitCommand() {
        Task {
            await model.submitCommand()
        }
    }

    private func retryConnection() {
        Task { await model.activityStore?.retryConnection() }
    }

    private func submitPendingAnswers(
        _ interactionID: String,
        _ answers: [String: [String]]
    ) async throws {
        try await model.submitPendingAnswers(
            interactionID: interactionID,
            answers: answers
        )
    }

    private func submitPendingDecision(
        _ interactionID: String,
        _ decision: RelayPendingApprovalDecision
    ) async throws {
        try await model.submitPendingDecision(
            interactionID: interactionID,
            decision: decision
        )
    }

    private func open(_ task: RelayTaskActivity) async throws {
        let action = RelayTaskOpenAction(
            openURL: NSWorkspace.shared.open,
            markRead: { threadID in
                await model.activityStore?.markRead(threadID: threadID)
            }
        )
        try await action(task)
    }

    private func markRead(_ task: RelayTaskActivity) async {
        await model.activityStore?.markRead(threadID: task.id)
    }

    private func send(
        _ task: RelayTaskActivity,
        prompt: String
    ) async throws {
        guard let store = model.activityStore else {
            throw ActionError.activityUnavailable
        }
        try await store.send(threadID: task.id, prompt: prompt)
    }

    private func interrupt(_ task: RelayTaskActivity) async throws {
        guard let store = model.activityStore else {
            throw ActionError.activityUnavailable
        }
        try await store.interrupt(threadID: task.id)
    }
}

private extension RelayNotchPanelHost {
    enum ActionError: LocalizedError {
        case activityUnavailable

        var errorDescription: String? {
            "Codex task actions are unavailable."
        }
    }
}
