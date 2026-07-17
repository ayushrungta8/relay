import RelayCore
import SwiftUI

struct RelayTaskRail: View {
    let tasks: [RelayTaskActivity]
    let selectedID: String?
    let select: (RelayTaskActivity) -> Void

    var body: some View {
        ScrollView {
            LazyVStack(spacing: 4) {
                ForEach(tasks) { task in
                    RelayTaskRow(
                        task: task,
                        isSelected: task.id == selectedID,
                        select: { select(task) }
                    )
                }
            }
            .padding(8)
        }
        .scrollIndicators(.never)
        .background(RelayPalette.shell.opacity(0.72))
        .accessibilityLabel("Codex tasks")
    }
}
