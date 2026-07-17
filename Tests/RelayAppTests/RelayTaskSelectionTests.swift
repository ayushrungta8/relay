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

    @Test
    func operationStateKeepsSubmissionAndErrorsScopedToTheirTask() {
        var state = RelayTaskOperationState()

        let beganFirst = state.beginSending(taskID: "first")
        let rejectedDuplicate = !state.beginSending(taskID: "first")
        let beganSecond = state.beginSending(taskID: "second")

        #expect(beganFirst)
        #expect(rejectedDuplicate)
        #expect(beganSecond)

        state.recordError("First failed", taskID: "first")
        #expect(state.error(taskID: "second") == nil)
        #expect(state.error(taskID: "first") == "First failed")

        state.finishSending(taskID: "first", error: nil)
        let beganFirstAgain = state.beginSending(taskID: "first")
        #expect(beganFirstAgain)
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
