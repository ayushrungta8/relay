import RelayCore
import SwiftUI

struct RelayTaskRow: View {
    let task: RelayTaskActivity
    let isSelected: Bool
    let select: () -> Void

    var body: some View {
        Button(action: select) {
            HStack(alignment: .top, spacing: 9) {
                RelayStatusSymbol(state: task.attentionState)
                    .labelStyle(.iconOnly)
                    .font(.caption)
                    .frame(width: 16)

                VStack(alignment: .leading, spacing: 4) {
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        Text(RelayActivityPresentation.title(for: task))
                            .font(.callout.weight(.semibold))
                            .foregroundStyle(RelayPalette.primaryText)
                            .lineLimit(1)

                        Spacer(minLength: 4)

                        Text(updatedDate, style: .relative)
                            .font(.caption2)
                            .foregroundStyle(RelayPalette.tertiaryText)
                            .monospacedDigit()
                    }

                    Text(updateCopy)
                        .font(.caption)
                        .foregroundStyle(RelayPalette.secondaryText)
                        .lineLimit(1)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 9)
            .contentShape(.rect)
            .background(
                isSelected
                    ? RelayPalette.accent.opacity(0.24)
                    : Color.clear,
                in: .rect(cornerRadius: 9)
            )
            .overlay {
                if isSelected {
                    RoundedRectangle(cornerRadius: 9)
                        .stroke(RelayPalette.accent.opacity(0.5), lineWidth: 1)
                }
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(accessibilityLabel)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    private var updatedDate: Date {
        Date(timeIntervalSince1970: TimeInterval(task.thread.updatedAt))
    }

    private var updateCopy: String {
        let update = task.latestUpdate?.trimmingCharacters(
            in: .whitespacesAndNewlines
        )
        if let update, !update.isEmpty { return update }
        return RelayAccessibilityContract.status(for: task.attentionState).label
    }

    private var accessibilityLabel: String {
        let title = RelayActivityPresentation.title(for: task)
        let status = RelayAccessibilityContract.status(for: task.attentionState)
            .label
        return "\(title), \(status), updated \(updatedDate.formatted(.relative(presentation: .named)))"
    }
}
