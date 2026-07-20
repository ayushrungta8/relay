import RelayCore
import SwiftUI

struct RelaySelectedTaskView: View {
    let task: RelayTaskActivity
    let tokenUsage: RelayThreadTokenUsage?
    let pendingInteractions: [RelayPendingInteraction]
    let drafts: RelayPanelDraftStore
    let actions: RelayTaskActions
    @Binding var operationState: RelayTaskOperationState
    let submitPendingAnswers:
        (String, [String: [String]]) async throws -> Void
    let submitPendingDecision:
        (String, RelayPendingApprovalDecision) async throws -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    var body: some View {
        GeometryReader { geometry in
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    statusHeader

                    Spacer(minLength: 24)

                    VStack(alignment: .leading, spacing: 14) {
                        contextUsage
                        actionRegion
                    }
                }
                .padding(20)
                .frame(
                    minHeight: geometry.size.height,
                    alignment: .top
                )
                .id(task.id)
                .transition(reduceMotion ? .opacity : .relayTaskDetail)
            }
            .scrollIndicators(.never)
        }
        .background(RelayPalette.detailSurface)
        .animation(detailAnimation, value: task.id)
        .onChange(of: task.id, initial: true) { _, _ in
            synchronizeFollowUp()
        }
        .onChange(of: task.attentionReason) { _, _ in
            synchronizeFollowUp()
        }
        .onChange(of: allowsTaskManagement) { _, _ in
            synchronizeFollowUp()
        }
    }

    private var statusHeader: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label(
                statusTitle,
                systemImage: RelayAccessibilityContract.status(
                    for: task.attentionState
                ).systemImage
            )
            .font(.callout)
            .foregroundStyle(statusColor)

            Text(RelayActivityPresentation.title(for: task))
                .font(.title2)
                .foregroundStyle(RelayPalette.primaryText)
                .lineLimit(2)

            Text(updateCopy)
                .font(.callout)
                .foregroundStyle(RelayPalette.secondaryText)
                .lineLimit(3)
                .textSelection(.enabled)

            HStack(spacing: 16) {
                Text(projectName)
                Text("Updated \(updatedDate.formatted(.relative(presentation: .named)))")
            }
            .font(.callout)
            .foregroundStyle(RelayPalette.secondaryText)
            .lineLimit(1)
        }
    }

    @ViewBuilder
    private var contextUsage: some View {
        if let contextPercentage = tokenUsage?.contextPercentage {
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text("Context used")
                    Spacer()
                    Text(
                        contextPercentage / 100,
                        format: .percent.precision(.fractionLength(0))
                    )
                    .monospacedDigit()
                }
                .font(.callout)
                .foregroundStyle(RelayPalette.primaryText)

                RelayProgressBar(
                    progress: clampedContextProgress,
                    colors: [
                        RelayPalette.accent,
                        RelayPalette.accentHighlight,
                    ]
                )
                    .id(reduceMotion ? contextPercentage : 0)
                    .transition(.opacity)
                    .animation(contextAnimation, value: contextPercentage)
                    .accessibilityLabel("Latest turn context")
                    .accessibilityValue(
                        "\(Int(contextPercentage.rounded())) percent used"
                    )
            }
        } else {
            Label(
                "Context unavailable",
                systemImage: "gauge.with.dots.needle.0percent"
            )
            .font(.caption)
            .foregroundStyle(RelayPalette.tertiaryText)
        }
    }

    @ViewBuilder
    private var actionRegion: some View {
        if task.attentionReason == .inferredReplyRequest {
            inferredReplyActions
        } else if task.attentionState == .needsInput {
            if pendingInteractions.isEmpty {
                pendingInteraction(
                    RelayPendingInteractionPresentation(
                        task: task,
                        ownedInteraction: nil
                    )
                )
            } else {
                ForEach(pendingInteractions) { interaction in
                    pendingInteraction(
                        RelayPendingInteractionPresentation(
                            task: task,
                            ownedInteraction: interaction
                        )
                    )
                    .id(interaction.id)
                }
            }
        } else {
            taskActions
        }

        if let errorMessage = operationState.error(taskID: task.id) {
            Label(errorMessage, systemImage: "exclamationmark.triangle")
                .font(.caption)
                .foregroundStyle(RelayPalette.failed)
                .accessibilityLabel("Task action failed: \(errorMessage)")
        }
    }

    private var inferredReplyActions: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Codex is waiting for your reply.")
                .font(.callout)
                .foregroundStyle(RelayPalette.secondaryText)
            taskActions
        }
    }

    private var taskActions: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Button("Open task", systemImage: "arrow.up.forward.app") {
                    perform { try await actions.open(task) }
                }
                .buttonStyle(.borderedProminent)
                .tint(RelayPalette.accent)
                .foregroundStyle(RelayPalette.primaryText)

                Button(
                    task.attentionReason == .inferredReplyRequest
                        ? "Reply"
                        : "Follow up",
                    systemImage: "paperplane"
                ) {
                    drafts.beginFollowUp(threadID: task.id)
                }
                .buttonStyle(.bordered)

                if task.thread.status == .active {
                    Button("Interrupt", systemImage: "stop.circle") {
                        perform { try await actions.interrupt(task) }
                    }
                    .buttonStyle(.bordered)
                }

                if task.hasUnreadCompletion
                    || task.attentionReason == .inferredReplyRequest {
                    Button(
                        task.attentionReason == .inferredReplyRequest
                            ? "Dismiss"
                            : "Mark read",
                        systemImage: "checkmark"
                    ) {
                        Task { await actions.markRead(task) }
                    }
                    .buttonStyle(.bordered)
                }
            }
            .controlSize(.small)

            if followUp.isComposing {
                HStack(spacing: 8) {
                    TextField(
                        "Follow up on this task…",
                        text: followUpBinding,
                        axis: .vertical
                    )
                    .textFieldStyle(.plain)
                    .lineLimit(1...2)
                    .onSubmit(sendFollowUp)
                    .disabled(operationState.isSending(taskID: task.id))

                    Button(
                        "Send follow-up",
                        systemImage: "arrow.up",
                        action: sendFollowUp
                    )
                    .labelStyle(.iconOnly)
                    .buttonStyle(.borderedProminent)
                    .disabled(!canSend)

                    Button(
                        "Cancel follow-up",
                        systemImage: "xmark",
                        action: discardFollowUp
                    )
                    .labelStyle(.iconOnly)
                    .buttonStyle(.plain)
                }
                .padding(9)
                .background(
                    RelayPalette.elevatedSurface,
                    in: .rect(cornerRadius: 8)
                )
            }
        }
    }

    private func pendingInteraction(
        _ presentation: RelayPendingInteractionPresentation
    ) -> some View {
        RelayPendingInteractionView(
            presentation: presentation,
            drafts: drafts,
            openInCodex: { try await actions.open(task) },
            submitAnswers: submitPendingAnswers,
            submitDecision: submitPendingDecision
        )
    }

    private var ownedInteractionPresentations:
        [RelayPendingInteractionPresentation] {
        pendingInteractions.map {
            RelayPendingInteractionPresentation(
                task: task,
                ownedInteraction: $0
            )
        }
    }

    private var allowsTaskManagement: Bool {
        if task.attentionReason == .inferredReplyRequest { return true }
        guard task.attentionState == .needsInput else { return true }
        guard !ownedInteractionPresentations.isEmpty else { return false }
        return ownedInteractionPresentations.allSatisfy(\.allowsTaskManagement)
    }

    private var updatedDate: Date {
        Date(timeIntervalSince1970: TimeInterval(task.thread.updatedAt))
    }

    private var projectName: String {
        let name = URL(filePath: task.thread.cwd).lastPathComponent
        return name.isEmpty ? task.thread.cwd : name
    }

    private var updateCopy: String {
        let update = task.latestUpdate?.trimmingCharacters(
            in: .whitespacesAndNewlines
        )
        if let update, !update.isEmpty { return update }
        return switch task.attentionState {
        case .needsInput: "Codex is waiting for your response."
        case .failed: "Codex reported a task failure."
        case .ready: "Completed; open the task for details."
        case .running: "Working; no progress update yet."
        case .idle: "No recent progress update."
        }
    }

    private var statusTitle: String {
        if task.attentionReason == .inferredReplyRequest {
            return "Needs your reply"
        }
        return switch task.attentionState {
        case .needsInput: "Needs your response"
        case .failed: "Task failed"
        case .ready: "Ready to review"
        case .running: "Running"
        case .idle: "Recent activity"
        }
    }

    private var statusColor: Color {
        switch task.attentionState {
        case .needsInput: RelayPalette.needsInput
        case .failed: RelayPalette.failed
        case .ready: RelayPalette.ready
        case .running: RelayPalette.running
        case .idle: RelayPalette.secondaryText
        }
    }

    private var clampedContextProgress: Double {
        min(max((tokenUsage?.contextPercentage ?? 0) / 100, 0), 1)
    }

    private var detailAnimation: Animation {
        reduceMotion
            ? .linear(duration: 0.12)
            : .easeOut(duration: 0.18)
    }

    private var contextAnimation: Animation {
        reduceMotion
            ? .linear(duration: 0.12)
            : .easeInOut(duration: 0.24)
    }

    private var followUp: RelayTaskCardFollowUpState {
        drafts.followUp(threadID: task.id)
    }

    private var followUpBinding: Binding<String> {
        Binding(
            get: { drafts.followUp(threadID: task.id).draft },
            set: { drafts.setFollowUp($0, threadID: task.id) }
        )
    }

    private var canSend: Bool {
        !followUp.draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !operationState.isSending(taskID: task.id)
    }

    private func synchronizeFollowUp() {
        drafts.synchronizeFollowUp(
            threadID: task.id,
            allowsTaskManagement: allowsTaskManagement
        )
        if task.attentionReason == .inferredReplyRequest {
            drafts.beginFollowUp(threadID: task.id)
        }
    }

    private func sendFollowUp() {
        let prompt = followUp.draft.trimmingCharacters(
            in: .whitespacesAndNewlines
        )
        let selectedTask = task
        let taskID = selectedTask.id
        let canManage = allowsTaskManagement
        guard canManage, !prompt.isEmpty,
              operationState.beginSending(taskID: taskID) else { return }
        Task {
            do {
                try await actions.send(selectedTask, prompt)
                drafts.discardFollowUp(threadID: taskID)
                operationState.finishSending(taskID: taskID, error: nil)
            } catch {
                operationState.finishSending(
                    taskID: taskID,
                    error: canManage ? error.localizedDescription : nil
                )
            }
        }
    }

    private func discardFollowUp() {
        drafts.discardFollowUp(threadID: task.id)
    }

    private func perform(_ operation: @escaping () async throws -> Void) {
        let taskID = task.id
        operationState.recordError(nil, taskID: taskID)
        Task {
            do {
                try await operation()
            } catch {
                operationState.recordError(
                    error.localizedDescription,
                    taskID: taskID
                )
            }
        }
    }
}
