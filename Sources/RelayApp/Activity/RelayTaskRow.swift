import RelayCore
import SwiftUI

struct RelayTaskRow: View {
    let task: RelayTaskActivity
    let isSelected: Bool
    let select: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isHovering = false

    var body: some View {
        Button(action: select) {
            HStack(alignment: .top, spacing: 9) {
                ZStack {
                    Circle()
                        .fill(statusColor.opacity(isSelected ? 0.22 : 0))
                        .frame(width: 17, height: 17)

                    Circle()
                        .fill(statusColor)
                        .frame(width: 7, height: 7)
                        .shadow(
                            color: statusColor.opacity(isSelected ? 0.62 : 0),
                            radius: 5
                        )
                }
                    .frame(width: 17, height: 17)
                    .padding(.top, 1)
                    .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: 4) {
                    Text(RelayActivityPresentation.title(for: task))
                        .font(.callout.weight(.semibold))
                        .foregroundStyle(RelayPalette.primaryText)
                        .lineLimit(1)

                    Text(metadataCopy)
                        .font(.caption)
                        .foregroundStyle(RelayPalette.secondaryText)
                        .lineLimit(1)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 10)
            .contentShape(.rect)
            .background(
                rowSurface,
                in: .rect(cornerRadius: 10)
            )
            .overlay {
                if isSelected {
                    RoundedRectangle(cornerRadius: 10)
                        .stroke(
                            RelayPalette.selectedBorder,
                            lineWidth: 1
                        )
                }
            }
        }
        .buttonStyle(.plain)
        .onHover { isHovering = $0 }
        .animation(rowAnimation, value: isHovering)
        .animation(rowAnimation, value: isSelected)
        .accessibilityLabel(accessibilityLabel)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    private var rowSurface: Color {
        if isSelected { return RelayPalette.selectedSurface }
        if isHovering { return RelayPalette.hoverSurface }
        return .clear
    }

    private var rowAnimation: Animation? {
        reduceMotion ? nil : .easeOut(duration: 0.16)
    }

    private var updatedDate: Date {
        Date(timeIntervalSince1970: TimeInterval(task.thread.updatedAt))
    }

    private var metadataCopy: String {
        switch task.attentionState {
        case .needsInput:
            "Needs your approval"
        case .failed:
            "Failed · \(updatedDate.formatted(.relative(presentation: .numeric)))"
        case .ready:
            "Complete · unread"
        case .running:
            "Running · \(updatedDate.formatted(.relative(presentation: .numeric)))"
        case .idle:
            "Recent · \(updatedDate.formatted(.relative(presentation: .numeric)))"
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

    private var accessibilityLabel: String {
        let title = RelayActivityPresentation.title(for: task)
        let status = RelayAccessibilityContract.status(for: task.attentionState)
            .label
        return "\(title), \(status), updated \(updatedDate.formatted(.relative(presentation: .named)))"
    }
}
