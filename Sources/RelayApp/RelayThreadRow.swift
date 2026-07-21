import RelayCore
import SwiftUI

struct RelayThreadRow: View {
    let thread: CodexThread
    let action: () -> Void

    @State private var isHovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 11) {
                Circle()
                    .fill(statusColor)
                    .frame(width: 8, height: 8)
                    .shadow(
                        color: statusColor.opacity(
                            thread.status == .active ? 0.45 : 0
                        ),
                        radius: 3
                    )
                    .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: 4) {
                    Text(title)
                        .font(.body.weight(.medium))
                        .foregroundStyle(.primary)
                        .lineLimit(1)

                    HStack(spacing: 5) {
                        Text(projectName)
                            .lineLimit(1)
                        Text("·")
                            .accessibilityHidden(true)
                        Text(
                            Date(
                                timeIntervalSince1970:
                                    TimeInterval(thread.updatedAt)
                            ),
                            style: .relative
                        )
                    }
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }

                Spacer(minLength: 8)

                Image(systemName: "arrow.up.right")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(
                        isHovering ? RelayPalette.accent : Color.secondary
                    )
                    .opacity(isHovering ? 1 : 0.45)
                    .accessibilityHidden(true)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 10)
            .frame(minHeight: 58)
            .contentShape(.rect)
            .background(
                isHovering ? RelayPalette.hoverSurface : .clear,
                in: .rect(cornerRadius: 9)
            )
        }
        .buttonStyle(.plain)
        .onHover { isHovering = $0 }
        .accessibilityLabel("\(title), \(projectName), \(statusLabel)")
        .accessibilityHint("Opens this task in Codex")
    }

    private var title: String {
        let name = thread.name?.trimmingCharacters(
            in: .whitespacesAndNewlines
        )
        if let name, !name.isEmpty {
            return name
        }

        let preview = thread.preview.trimmingCharacters(
            in: .whitespacesAndNewlines
        )
        return preview.isEmpty ? "Untitled Codex task" : preview
    }

    private var projectName: String {
        RelayProjectPresentation.name(for: thread.cwd)
    }

    private var statusColor: Color {
        switch thread.status {
        case .active:
            RelayPalette.accent
        case .idle:
            .blue
        case .systemError:
            .red
        case .notLoaded, .unknown:
            .secondary
        }
    }

    private var statusLabel: String {
        switch thread.status {
        case .active:
            "active"
        case .idle:
            "idle"
        case .notLoaded:
            "not currently loaded"
        case .systemError:
            "error"
        case .unknown:
            "unknown status"
        }
    }
}
