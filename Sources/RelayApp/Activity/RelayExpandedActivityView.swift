import RelayCore
import SwiftUI

struct RelayExpandedActivityView: View {
    let activity: RelayActivityPresentation
    let capacity: RelayCapacityPresentation
    let tokenUsageByThreadID: [String: RelayThreadTokenUsage]
    let pendingInteractionsByThreadID: [String: RelayPendingInteraction]
    let actions: RelayTaskActions
    @Binding var commandText: String
    let composerPhase: RelayComposerPhase
    let submitCommand: () -> Void
    let submitPendingAnswers:
        (String, [String: [String]]) async throws -> Void
    let submitPendingDecision:
        (String, RelayPendingApprovalDecision) async throws -> Void
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
                            pendingInteractionsByThreadID:
                                pendingInteractionsByThreadID,
                            actions: actions,
                            submitPendingAnswers: submitPendingAnswers,
                            submitPendingDecision: submitPendingDecision
                        )

                        TaskSection(
                            title: "Running",
                            systemImage: "ellipsis.circle",
                            tasks: activity.runningTasks,
                            tokenUsageByThreadID: tokenUsageByThreadID,
                            pendingInteractionsByThreadID:
                                pendingInteractionsByThreadID,
                            actions: actions,
                            submitPendingAnswers: submitPendingAnswers,
                            submitPendingDecision: submitPendingDecision
                        )

                        TaskSection(
                            title: "Recent",
                            systemImage: "clock",
                            tasks: activity.recentTasks,
                            tokenUsageByThreadID: tokenUsageByThreadID,
                            pendingInteractionsByThreadID:
                                pendingInteractionsByThreadID,
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
        let pendingInteractionsByThreadID:
            [String: RelayPendingInteraction]
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
                        RelayTaskCard(
                            task: task,
                            tokenUsage: tokenUsageByThreadID[task.id],
                            layout: .expanded,
                            actions: actions,
                            primaryAction: {}
                        )

                        if task.attentionState == .needsInput {
                            RelayPendingInteractionView(
                                presentation:
                                    RelayPendingInteractionPresentation(
                                        task: task,
                                        ownedInteraction:
                                            pendingInteractionsByThreadID[task.id]
                                    ),
                                openInCodex: {
                                    try await actions.open(task)
                                },
                                submitAnswers: submitPendingAnswers,
                                submitDecision: submitPendingDecision
                            )
                        }
                    }
                }
            }
        }
    }
}

private struct RelayPendingInteractionView: View {
    let presentation: RelayPendingInteractionPresentation
    let openInCodex: () async throws -> Void
    let submitAnswers: (String, [String: [String]]) async throws -> Void
    let submitDecision:
        (String, RelayPendingApprovalDecision) async throws -> Void

    @State private var answers: [String: String] = [:]
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

                    ForEach(question.options, id: \.label) { option in
                        Button {
                            answers[question.id] = option.label
                        } label: {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(option.label)
                                Text(option.description)
                                    .font(.caption)
                                    .foregroundStyle(
                                        RelayPalette.secondaryText
                                    )
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .buttonStyle(.bordered)
                    }

                    if question.options.isEmpty || question.allowsOther {
                        if question.isSecret {
                            SecureField(
                                "Answer",
                                text: answerBinding(for: question.id)
                            )
                        } else {
                            TextField(
                                "Answer",
                                text: answerBinding(for: question.id)
                            )
                        }
                    }
                }
            }

            Button("Submit answer", systemImage: "paperplane.fill") {
                perform {
                    let payload = Dictionary(
                        uniqueKeysWithValues: questions.map {
                            ($0.id, [answers[$0.id] ?? ""])
                        }
                    )
                    try await submitAnswers(interaction.id, payload)
                }
            }
            .buttonStyle(.borderedProminent)
            .disabled(
                questions.contains {
                    answers[$0.id]?
                        .trimmingCharacters(in: .whitespacesAndNewlines)
                        .isEmpty != false
                }
            )
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
        Binding(
            get: { answers[questionID] ?? "" },
            set: { answers[questionID] = $0 }
        )
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
