import AppKit
import RelayCore
import SwiftUI

struct RelayFullWidthTaskListHeader: View {
    let taskCount: Int

    var body: some View {
        HStack(spacing: 8) {
            Text("Tasks")
            Text(taskCount, format: .number)
                .monospacedDigit()
                .foregroundStyle(RelayPalette.tertiaryText)

            Spacer(minLength: 12)

            Text("PROJECT")
                .frame(width: 60, alignment: .leading)
            Text("CONTEXT")
                .frame(width: 54, alignment: .trailing)
            Text("UPDATED")
                .frame(width: 62, alignment: .trailing)
            Text("STATUS")
                .frame(width: 80, alignment: .leading)
            Color.clear.frame(width: 12)
        }
        .font(.caption.weight(.medium))
        .foregroundStyle(RelayPalette.secondaryText)
        .padding(.horizontal, 16)
        .frame(height: 38)
    }
}

struct RelayFullWidthTaskRow: View {
    let task: RelayTaskActivity
    let tokenUsage: RelayThreadTokenUsage?
    let isExpanded: Bool
    let select: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isHovering = false

    var body: some View {
        Button(action: select) {
            HStack(spacing: 8) {
                statusSymbol

                VStack(alignment: .leading, spacing: 3) {
                    Text(RelayActivityPresentation.title(for: task))
                        .font(.body.weight(.semibold))
                        .foregroundStyle(RelayPalette.primaryText)
                        .lineLimit(1)

                    if !isExpanded {
                        Text(RelayRichText.plain(summary))
                            .font(.callout)
                            .foregroundStyle(RelayPalette.secondaryText)
                            .lineLimit(1)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                Text(projectName)
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .frame(width: 60, alignment: .leading)

                Text(contextCopy)
                    .monospacedDigit()
                    .frame(width: 54, alignment: .trailing)

                Text(updatedCopy)
                    .monospacedDigit()
                    .lineLimit(1)
                    .frame(width: 62, alignment: .trailing)

                HStack(spacing: 5) {
                    Circle()
                        .fill(statusColor)
                        .frame(width: 6, height: 6)
                    Text(statusTitle)
                        .lineLimit(1)
                }
                .foregroundStyle(statusColor)
                .frame(width: 80, alignment: .leading)

                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(RelayPalette.tertiaryText)
                    .rotationEffect(.degrees(isExpanded ? 90 : 0))
                    .frame(width: 12)
                    .accessibilityHidden(true)
            }
            .font(.callout)
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .contentShape(.rect)
            .background(rowSurface)
        }
        .buttonStyle(.plain)
        .onContinuousHover { phase in
            switch phase {
            case .active:
                isHovering = true
                NSCursor.pointingHand.set()
            case .ended:
                isHovering = false
                NSCursor.arrow.set()
            }
        }
        .animation(rowAnimation, value: isHovering)
        .animation(rowAnimation, value: isExpanded)
        .accessibilityLabel(accessibilityLabel)
        .accessibilityHint(
            isExpanded ? "Collapse task details" : "Show task details"
        )
        .accessibilityAddTraits(isExpanded ? .isSelected : [])
    }

    private var statusSymbol: some View {
        ZStack {
            Circle()
                .fill(statusColor.opacity(isExpanded ? 0.20 : 0.10))
                .frame(width: 24, height: 24)

            Image(
                systemName: RelayAccessibilityContract.status(
                    for: task.attentionState
                ).systemImage
            )
            .font(.system(size: 10, weight: .bold))
            .foregroundStyle(statusColor)
        }
        .accessibilityHidden(true)
    }

    private var summary: String {
        let update = task.latestUpdate?.trimmingCharacters(
            in: .whitespacesAndNewlines
        )
        if let update, !update.isEmpty { return update }
        return switch task.attentionState {
        case .needsInput: "Codex is waiting for your response."
        case .failed: task.latestTurnError ?? "Codex reported a task failure."
        case .ready: "Completed and ready to review."
        case .running: "Working; no progress update yet."
        case .idle: "No recent progress update."
        }
    }

    private var projectName: String {
        RelayProjectPresentation.name(for: task.thread.cwd)
    }

    private var contextCopy: String {
        guard let percentage = tokenUsage?.contextPercentage else { return "—" }
        return (percentage / 100).formatted(
            .percent.precision(.fractionLength(0))
        )
    }

    private var updatedCopy: String {
        let elapsed = max(0, Date().timeIntervalSince(updatedDate))
        switch elapsed {
        case ..<5:
            return "now"
        case ..<60:
            return "\(Int(elapsed))s"
        case ..<3_600:
            return "\(Int(elapsed / 60))m"
        case ..<86_400:
            return "\(Int(elapsed / 3_600))h"
        case ..<2_592_000:
            return "\(Int(elapsed / 86_400))d"
        default:
            return updatedDate.formatted(
                .dateTime.month(.abbreviated).day()
            )
        }
    }

    private var updatedDate: Date {
        Date(timeIntervalSince1970: TimeInterval(task.thread.updatedAt))
    }

    private var accessibleUpdatedCopy: String {
        updatedDate.formatted(.relative(presentation: .numeric))
    }

    private var statusTitle: String {
        if task.attentionReason == .inferredReplyRequest { return "Reply" }
        return switch task.attentionState {
        case .needsInput: "Needs input"
        case .failed: "Failed"
        case .ready: "Complete"
        case .running: "Running"
        case .idle: "Recent"
        }
    }

    private var statusColor: Color {
        switch task.attentionState {
        case .needsInput: RelayPalette.needsInput
        case .failed: RelayPalette.failed
        case .ready: RelayPalette.ready
        case .running: RelayPalette.running
        case .idle: RelayPalette.idle
        }
    }

    private var rowSurface: Color {
        if isExpanded { return RelayPalette.elevatedSurface }
        if isHovering { return RelayPalette.hoverSurface }
        return RelayPalette.detailSurface
    }

    private var rowAnimation: Animation? {
        reduceMotion ? nil : .easeOut(duration: 0.16)
    }

    private var accessibilityLabel: String {
        let title = RelayActivityPresentation.title(for: task)
        let context: String
        if let percentage = tokenUsage?.contextPercentage {
            context = "\(Int(percentage.rounded())) percent context"
        } else {
            context = "context unavailable"
        }
        return "\(title), \(statusTitle), \(context), updated \(accessibleUpdatedCopy)"
    }
}
