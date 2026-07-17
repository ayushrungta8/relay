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
    let submitCommand: () -> Void
    let retryConnection: () -> Void
    let submitPendingAnswers:
        (String, [String: [String]]) async throws -> Void
    let submitPendingDecision:
        (String, RelayPendingApprovalDecision) async throws -> Void
    let collapse: () -> Void

    @State private var showsUsageDetail = false

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

            Divider()
                .overlay(RelayPalette.hairline)

            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    if let connection, connection.isVisible {
                        RelayConnectionStatusView(
                            presentation: connection,
                            retry: retryConnection
                        )
                    }

                    if !drafts.orphanedDrafts.isEmpty {
                        RelayOrphanedDraftsView(drafts: drafts)
                    }

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
                            pendingInteractions: pendingInteractions,
                            drafts: drafts,
                            actions: actions,
                            submitPendingAnswers: submitPendingAnswers,
                            submitPendingDecision: submitPendingDecision
                        )

                        TaskSection(
                            title: "Running",
                            systemImage: "ellipsis.circle",
                            tasks: activity.runningTasks,
                            tokenUsageByThreadID: tokenUsageByThreadID,
                            pendingInteractions: pendingInteractions,
                            drafts: drafts,
                            actions: actions,
                            submitPendingAnswers: submitPendingAnswers,
                            submitPendingDecision: submitPendingDecision
                        )

                        TaskSection(
                            title: "Recent",
                            systemImage: "clock",
                            tasks: activity.recentTasks,
                            tokenUsageByThreadID: tokenUsageByThreadID,
                            pendingInteractions: pendingInteractions,
                            drafts: drafts,
                            actions: actions,
                            submitPendingAnswers: submitPendingAnswers,
                            submitPendingDecision: submitPendingDecision
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
            }
            .scrollIndicators(.never)

            Divider()
                .overlay(RelayPalette.hairline)

            VStack(spacing: 0) {
                if let latestResponse,
                   !latestResponse.trimmingCharacters(
                       in: .whitespacesAndNewlines
                   ).isEmpty {
                    RelayControllerAnswerView(answer: latestResponse)
                    Divider().overlay(RelayPalette.hairline)
                }

                RelayCommandComposerView(
                    text: $commandText,
                    phase: composerPhase,
                    submit: submitCommand
                )
            }
            .background(RelayPalette.elevatedSurface)
        }
    }

    private var summaryCopy: String {
        activity.expandedSummaryCopy
    }

    private func toggleUsageDetail() {
        showsUsageDetail.toggle()
    }
}

private extension RelayExpandedActivityView {
    struct TaskSection: View {
        let title: String
        let systemImage: String
        let tasks: [RelayTaskActivity]
        let tokenUsageByThreadID: [String: RelayThreadTokenUsage]
        let pendingInteractions: [RelayPendingInteraction]
        let drafts: RelayPanelDraftStore
        let actions: RelayTaskActions
        let submitPendingAnswers:
            (String, [String: [String]]) async throws -> Void
        let submitPendingDecision:
            (String, RelayPendingApprovalDecision) async throws -> Void

        var body: some View {
            if !tasks.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Label(title, systemImage: systemImage)
                        .font(.callout)
                        .bold()
                        .foregroundStyle(RelayPalette.secondaryText)
                        .accessibilityAddTraits(.isHeader)

                    ForEach(tasks) { task in
                        let ownedInteractions = pendingInteractions.filter {
                            $0.threadID == task.id
                        }
                        let waitingPresentation =
                            task.attentionState == .needsInput
                                ? RelayPendingInteractionPresentation(
                                    task: task,
                                    ownedInteraction: ownedInteractions.first
                                )
                                : nil
                        RelayTaskCard(
                            task: task,
                            tokenUsage: tokenUsageByThreadID[task.id],
                            layout: .expanded,
                            actions: actions,
                            drafts: drafts,
                            primaryAction: {},
                            showsActionMenu:
                                waitingPresentation?.allowsTaskManagement
                                    ?? true
                        )

                        if let waitingPresentation {
                            if ownedInteractions.isEmpty {
                                pendingInteractionView(
                                    task: task,
                                    presentation: waitingPresentation
                                )
                            } else {
                                ForEach(ownedInteractions) { interaction in
                                    pendingInteractionView(
                                        task: task,
                                        presentation:
                                            RelayPendingInteractionPresentation(
                                                task: task,
                                                ownedInteraction: interaction
                                            )
                                    )
                                    .id(interaction.id)
                                }
                            }
                        }
                    }
                }
            }
        }

        private func pendingInteractionView(
            task: RelayTaskActivity,
            presentation: RelayPendingInteractionPresentation
        ) -> some View {
            RelayPendingInteractionView(
                presentation: presentation,
                drafts: drafts,
                openInCodex: {
                    try await actions.open(task)
                },
                submitAnswers: submitPendingAnswers,
                submitDecision: submitPendingDecision
            )
        }
    }
}

private struct RelayPendingInteractionView: View {
    let presentation: RelayPendingInteractionPresentation
    let drafts: RelayPanelDraftStore
    let openInCodex: () async throws -> Void
    let submitAnswers: (String, [String: [String]]) async throws -> Void
    let submitDecision:
        (String, RelayPendingApprovalDecision) async throws -> Void

    @State private var isSubmitting = false
    @State private var errorMessage: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(presentation.explanation)
                .font(.caption)
                .foregroundStyle(RelayPalette.secondaryText)

            switch presentation.action {
            case .openInCodex:
                Button("Open in Codex", systemImage: "arrow.up.forward.app") {
                    perform(openInCodex)
                }
            case .answerQuestions:
                questionControls
            case .reviewApproval:
                approvalControls
            case .resolving:
                Label("Resolving in Codex", systemImage: "hourglass")
                    .font(.callout)
            }

            if let errorMessage {
                Label(errorMessage, systemImage: "exclamationmark.triangle")
                    .font(.caption)
                    .foregroundStyle(RelayPalette.failed)
            }
        }
        .padding(12)
        .background(
            RelayPalette.elevatedSurface,
            in: .rect(cornerRadius: 10)
        )
        .disabled(isSubmitting)
        .onChange(of: presentation.interaction?.id) { _, interactionID in
            isSubmitting = false
            errorMessage = nil
            guard let interactionID else { return }
            _ = drafts.pendingDraft(interactionID: interactionID)
        }
    }

    @ViewBuilder
    private var questionControls: some View {
        if let interaction = presentation.interaction,
           case let .questions(questions) = interaction.kind {
            ForEach(questions) { question in
                VStack(alignment: .leading, spacing: 7) {
                    Text(question.header)
                        .font(.callout.bold())
                    Text(question.question)
                        .font(.caption)
                        .foregroundStyle(RelayPalette.secondaryText)

                    ForEach(
                        RelayPendingInteractionPresentation.options(
                            for: question
                        )
                    ) { entry in
                        let isSelected =
                            RelayPendingInteractionPresentation.isSelected(
                                entry,
                                for: question,
                                draft: answerDraft
                            )
                        Button {
                            drafts.setPendingAnswer(
                                entry.option.label,
                                questionID: question.id,
                                interactionID: interaction.id
                            )
                        } label: {
                            HStack {
                                VStack(alignment: .leading, spacing: 2) {
                                Text(entry.option.label)
                                Text(entry.option.description)
                                    .font(.caption)
                                    .foregroundStyle(
                                        RelayPalette.secondaryText
                                    )
                                }
                                Spacer()
                                if isSelected {
                                    Image(systemName: "checkmark.circle.fill")
                                        .accessibilityHidden(true)
                                }
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .buttonStyle(.bordered)
                        .tint(isSelected ? RelayPalette.accent : nil)
                        .accessibilityAddTraits(
                            isSelected ? .isSelected : []
                        )
                    }

                    if question.options.isEmpty || question.allowsOther {
                        if question.isSecret {
                            SecureField(
                                "Answer",
                                text: answerBinding(for: question.id)
                            )
                            .accessibilityLabel(
                                RelayPendingInteractionPresentation
                                    .answerAccessibilityLabel(for: question)
                            )
                        } else {
                            TextField(
                                "Answer",
                                text: answerBinding(for: question.id)
                            )
                            .accessibilityLabel(
                                RelayPendingInteractionPresentation
                                    .answerAccessibilityLabel(for: question)
                            )
                        }
                    }
                }
            }

            Button("Submit answer", systemImage: "paperplane.fill") {
                perform {
                    let payload = answerDraft.payload(questions: questions)
                    try await submitAnswers(interaction.id, payload)
                    drafts.discardPendingAnswers(
                        interactionID: interaction.id
                    )
                }
            }
            .buttonStyle(.borderedProminent)
            .disabled(
                !answerDraft.canSubmit(questions: questions)
            )

            Button("Cancel answer", systemImage: "xmark") {
                drafts.discardPendingAnswers(interactionID: interaction.id)
            }
            .buttonStyle(.bordered)
        }
    }

    @ViewBuilder
    private var approvalControls: some View {
        if let interaction = presentation.interaction,
           case let .approval(approval) = interaction.kind {
            Text(approval.title)
                .font(.callout.bold())
            if let detail = approval.detail {
                Text(detail)
                    .font(.caption.monospaced())
                    .textSelection(.enabled)
            }
            HStack {
                if approval.canApprove {
                    Button("Approve", systemImage: "checkmark") {
                        perform {
                            try await submitDecision(
                                interaction.id,
                                .approve
                            )
                        }
                    }
                    .buttonStyle(.borderedProminent)
                }
                if approval.canDecline {
                    Button("Decline", systemImage: "xmark") {
                        perform {
                            try await submitDecision(
                                interaction.id,
                                .decline
                            )
                        }
                    }
                    .buttonStyle(.bordered)
                }
            }
        }
    }

    private func answerBinding(for questionID: String) -> Binding<String> {
        guard let interactionID = presentation.interaction?.id else {
            return .constant("")
        }
        return Binding(
            get: { answerDraft.answer(for: questionID) },
            set: {
                drafts.setPendingAnswer(
                    $0,
                    questionID: questionID,
                    interactionID: interactionID
                )
            }
        )
    }

    private var answerDraft: RelayPendingAnswerDraft {
        guard let interactionID = presentation.interaction?.id else {
            return RelayPendingAnswerDraft(interactionID: nil)
        }
        return drafts.pendingDraft(interactionID: interactionID)
    }

    private func perform(
        _ operation: @escaping () async throws -> Void
    ) {
        guard !isSubmitting else { return }
        isSubmitting = true
        errorMessage = nil
        Task {
            do {
                try await operation()
            } catch {
                errorMessage = error.localizedDescription
            }
            isSubmitting = false
        }
    }
}
