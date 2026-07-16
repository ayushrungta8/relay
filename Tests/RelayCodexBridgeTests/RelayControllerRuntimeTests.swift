import Foundation
import RelayBrain
import RelayCodexBridge
import Testing

struct RelayControllerRuntimeTests {
    @Test
    func runsControllerToolCallsBeforeReturningTheFinalAnswer() async throws {
        let session = ControllerSessionStub()
        let operations = TaskOperationsStub()
        let runtime = RelayControllerRuntime(
            session: session,
            router: RelayToolCallRouter(operations: operations)
        )

        let answer = try await runtime.submit("What is running?")

        #expect(answer == "One task is active.")
        let completed = try #require(await session.completedResult())
        #expect(completed.success)
        #expect(completed.text.contains("task-1"))
        #expect(await operations.listCallCount() == 1)
    }
}

private actor ControllerSessionStub: RelayControllerSession {
    private var completed: RelayToolCallResult?

    func ensureControllerThread(
        configuration: RelayControllerConfiguration
    ) async throws -> RelayControllerThread {
        RelayControllerThread(id: "controller-1")
    }

    func submitUserText(
        _ text: String,
        to controller: RelayControllerThread
    ) async throws -> AsyncThrowingStream<RelayControllerEvent, any Error> {
        AsyncThrowingStream { continuation in
            continuation.yield(
                .dynamicToolCall(
                    RelayControllerToolCall(
                        id: "call-1",
                        toolName: "relay_list_tasks",
                        argumentsJSON: Data("{}".utf8)
                    )
                )
            )
            continuation.yield(.finalText("One task is active."))
            continuation.finish()
        }
    }

    func completeToolCall(
        _ call: RelayControllerToolCall,
        with result: RelayToolCallResult
    ) async throws {
        completed = result
    }

    func completedResult() -> RelayToolCallResult? {
        completed
    }
}

private actor TaskOperationsStub: RelayTaskOperations {
    private var listCalls = 0

    func listTasks() async throws -> [RelayTaskSummary] {
        listCalls += 1
        return [
            RelayTaskSummary(
                id: "task-1",
                title: "Build Relay",
                project: "/Users/test/Work/Relay",
                status: "active",
                updatedAt: Date(timeIntervalSince1970: 1_784_210_400)
            ),
        ]
    }

    func getTask(id: String) async throws -> RelayTaskSummary? {
        nil
    }

    func startTask(
        prompt: String,
        cwd: String
    ) async throws -> RelayTaskSummary {
        throw StubError.unexpected
    }

    func sendToTask(id: String, prompt: String) async throws {
        throw StubError.unexpected
    }

    func interruptTask(id: String) async throws {
        throw StubError.unexpected
    }

    func listCallCount() -> Int {
        listCalls
    }
}

private enum StubError: Error {
    case unexpected
}
