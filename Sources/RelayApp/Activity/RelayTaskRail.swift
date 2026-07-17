import RelayCore
import SwiftUI

struct RelayTaskRail: View {
    let tasks: [RelayTaskActivity]
    let selectedID: String?
    let select: (RelayTaskActivity) -> Void

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Tasks")
                Spacer()
                Text(tasks.count, format: .number)
                    .monospacedDigit()
            }
            .font(.callout)
            .foregroundStyle(RelayPalette.secondaryText)
            .padding(.horizontal, 18)
            .frame(height: 40)

            ScrollView {
                LazyVStack(spacing: 3) {
                    ForEach(tasks) { task in
                        RelayTaskRow(
                            task: task,
                            isSelected: task.id == selectedID,
                            select: { select(task) }
                        )
                    }
                }
                .padding(.horizontal, 10)
                .padding(.bottom, 10)
            }
            .scrollIndicators(.never)
        }
        .background(RelayPalette.railSurface)
        .accessibilityLabel("Codex tasks")
    }
}
