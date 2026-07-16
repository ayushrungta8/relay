import RelayCore
import SwiftUI

struct RelayTaskCard: View {
    enum Layout {
        case compact
        case expanded
    }

    let task: RelayTaskActivity
    let tokenUsage: RelayThreadTokenUsage?
    let layout: Layout
    let actions: RelayTaskActions
    let primaryAction: () -> Void
    var showsActionMenu = true

    @State private var isHovering = false
    @State private var isComposing = false
    @State private var isSending = false
    @State private var draft = ""
    @State private var errorMessage: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack(alignment: .top, spacing: 10) {
                Button(action: performPrimaryAction) {
                    VStack(alignment: .leading, spacing: 7) {
                        HStack(spacing: 7) {
                            RelayStatusSymbol(state: task.attentionState)
                                .font(.caption)

                            Spacer(minLength: 6)

                            Text(updatedDate, style: .relative)
                                .font(.caption)
                                .foregroundStyle(
                                    RelayPalette.tertiaryText
                                )
                        }

                        Text(RelayActivityPresentation.title(for: task))
                            .font(.body)
                            .bold()
                            .foregroundStyle(RelayPalette.primaryText)
                            .lineLimit(layout == .compact ? 1 : 2)

                        Text(updateCopy)
                            .font(.caption)
                            .foregroundStyle(RelayPalette.secondaryText)
                            .lineLimit(layout == .compact ? 1 : 2)
                            .frame(
                                maxWidth: .infinity,
                                alignment: .leading
                            )
                    }
                    .contentShape(.rect)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(accessibilityLabel)
                .accessibilityHint(primaryActionHint)

                if layout == .expanded, showsActionMenu {
                    Menu("Task actions", systemImage: "ellipsis") {
                        Button(
                            "Open in Codex",
                            systemImage: "arrow.up.forward.app",
                            action: openTask
                        )

                        Button(
                            "Send follow-up",
                            systemImage: "paperplane",
                            action: beginFollowUp
                        )

                        if task.thread.status == .active {
                            Button(
                                "Interrupt",
                                systemImage: "stop.circle",
                                action: interruptTask
                            )
                        }

                        if task.hasUnreadCompletion {
                            Button(
                                "Mark read",
                                systemImage: "checkmark",
                                action: markRead
                            )
                        }
                    }
                    .menuStyle(.borderlessButton)
                    .fixedSize()
                    .help("Task actions")
                }
            }

            if layout == .expanded {
                HStack(spacing: 8) {
                    Label(projectName, systemImage: "folder")
                        .lineLimit(1)

                    if let contextPercentage = tokenUsage?.contextPercentage {
                        Divider()
                            .frame(height: 12)

                        Label {
                            Text(
                                contextPercentage / 100,
                                format: .percent.precision(
                                    .fractionLength(0)
                                )
                            )
                            .monospacedDigit()
                        } icon: {
                            Image(systemName: "gauge.with.dots.needle.33percent")
                        }
                        .help("Context used by the latest turn")
                    } else {
                        Divider()
                            .frame(height: 12)

                        Label(
                            "Context unavailable",
                            systemImage: "gauge.with.dots.needle.0percent"
                        )
                    }
                }
                .font(.caption)
                .foregroundStyle(RelayPalette.tertiaryText)
            }

            if isComposing {
                HStack(spacing: 8) {
                    TextField(
                        "Follow up on this task…",
                        text: $draft,
                        axis: .vertical
                    )
                    .textFieldStyle(.plain)
                    .lineLimit(1...3)
                    .onSubmit(sendFollowUp)
                    .disabled(isSending)

                    Button(
                        "Send follow-up",
                        systemImage: "arrow.up",
                        action: sendFollowUp
                    )
                    .labelStyle(.iconOnly)
                    .buttonStyle(.borderedProminent)
                    .disabled(!canSend)
                }
                .padding(9)
                .background(
                    RelayPalette.shell,
                    in: .rect(cornerRadius: 8)
                )
            }

            if let errorMessage {
                Label(errorMessage, systemImage: "exclamationmark.triangle")
                    .font(.caption)
                    .foregroundStyle(RelayPalette.failed)
                    .accessibilityLabel("Task action failed: \(errorMessage)")
            }
        }
        .padding(layout == .compact ? 10 : 12)
        .frame(
            width: layout == .compact ? 220 : nil,
            alignment: .leading
        )
        .frame(
            maxWidth: layout == .expanded ? .infinity : nil,
            alignment: .leading
        )
        .background(
            isHovering
                ? RelayPalette.elevatedHover
                : RelayPalette.elevatedSurface,
            in: .rect(cornerRadius: 10)
        )
        .onHover { isHovering = $0 }
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
        if let update, !update.isEmpty {
            return update
        }
        return switch task.attentionState {
        case .needsInput:
            "Codex is waiting for your response."
        case .failed:
            "Codex reported a task failure."
        case .ready:
            "Completed; open the task for details."
        case .running:
            "Working; no progress update yet."
        case .idle:
            "No recent progress update."
        }
    }

    private var accessibilityLabel: String {
        let title = RelayActivityPresentation.title(for: task)
        let status = RelayStatusSymbol(state: task.attentionState).label
        return "\(title), \(status), \(updateCopy)"
    }

    private var primaryActionHint: String {
        layout == .compact
            ? "Expands the Relay activity center"
            : "Opens this task in Codex"
    }

    private var canSend: Bool {
        !draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !isSending
    }

    private func openTask() {
        errorMessage = nil
        Task {
            do {
                try await actions.open(task)
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }

    private func performPrimaryAction() {
        if layout == .compact {
            primaryAction()
        } else {
            openTask()
        }
    }

    private func beginFollowUp() {
        errorMessage = nil
        isComposing = true
    }

    private func markRead() {
        Task {
            await actions.markRead(task)
        }
    }

    private func interruptTask() {
        errorMessage = nil
        Task {
            do {
                try await actions.interrupt(task)
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }

    private func sendFollowUp() {
        let prompt = draft.trimmingCharacters(
            in: .whitespacesAndNewlines
        )
        guard !prompt.isEmpty, !isSending else { return }
        isSending = true
        errorMessage = nil
        Task {
            do {
                try await actions.send(task, prompt)
                draft = ""
                isComposing = false
            } catch {
                errorMessage = error.localizedDescription
            }
            isSending = false
        }
    }
}
