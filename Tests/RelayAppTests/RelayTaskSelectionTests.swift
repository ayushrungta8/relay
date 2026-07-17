import RelayCore
import Testing
@testable import RelayApp

@MainActor
struct RelayTaskSelectionTests {
    @Test
    func preservesPreferredTaskWhileItRemainsOrdered() {
        let first = task(id: "first")
        let second = task(id: "second")

        #expect(
            RelayTaskSelection.resolvedID(
                preferredID: second.id,
                orderedTasks: [first, second]
            ) == second.id
        )
    }

    @Test
    func fallsBackToFirstOrderedTaskWhenPreferenceDisappears() {
        let first = task(id: "first")
        let second = task(id: "second")

        #expect(
            RelayTaskSelection.resolvedID(
                preferredID: "missing",
                orderedTasks: [first, second]
            ) == first.id
        )
    }

    @Test
    func resolvesToNilWhenThereAreNoTasks() {
        #expect(
            RelayTaskSelection.resolvedID(
                preferredID: nil,
                orderedTasks: []
            ) == nil
        )
    }

    private func task(id: String) -> RelayTaskActivity {
        RelayTaskActivity(
            thread: CodexThread(
                id: id,
                name: id.capitalized,
                preview: id.capitalized,
                cwd: "/Users/example/Relay",
                updatedAt: 1,
                status: .idle
            )
        )
    }
}
