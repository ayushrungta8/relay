import Foundation
import Testing
@testable import RelayBrain

struct RelayToolCallRouterTests {
    @Test
    func recentTasksReturnsOnlyTasksUpdatedWithinRollingDay() async throws {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let task = makeTask(id: "task-1", status: "running")
        let old = makeTask(
            id: "old-task",
            status: "running",
            updatedAt: now.addingTimeInterval(-86_401)
        )
        let recent = RelayTaskSummary(
            id: task.id,
            title: task.title,
            project: task.project,
            status: task.status,
            updatedAt: now.addingTimeInterval(-86_400),
            latestUpdate: task.latestUpdate
        )
        let operations = TaskOperationsSpy(tasks: [old, recent])
        let router = RelayToolCallRouter(
            operations: operations,
            now: { now }
        )

        let result = await router.route(
            toolName: "relay_get_recent_tasks",
            argumentsJSON: "{}"
        )

        #expect(result.success)
        let object = try resultObject(result)
        #expect(object["ok"] as? Bool == true)
        #expect(object["tool"] as? String == "relay_get_recent_tasks")

        let tasks = try #require(object["tasks"] as? [[String: Any]])
        #expect(tasks.count == 1)
        #expect(tasks.first?["id"] as? String == "task-1")
        #expect(tasks.first?["status"] as? String == "running")

        let calls = await operations.recordedCalls()
        #expect(calls == [.list, .get(id: "task-1")])
    }

    @Test
    func runningTasksReturnsOnlyRecentRunningTasks() async throws {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let tasks = [
            makeTask(
                id: "running",
                status: "running",
                updatedAt: now.addingTimeInterval(-60)
            ),
            makeTask(
                id: "idle",
                status: "idle",
                updatedAt: now.addingTimeInterval(-60)
            ),
            makeTask(
                id: "old-running",
                status: "running",
                updatedAt: now.addingTimeInterval(-86_401)
            ),
        ]
        let router = RelayToolCallRouter(
            operations: TaskOperationsSpy(tasks: tasks),
            now: { now }
        )

        let result = await router.route(
            toolName: "relay_get_running_tasks",
            argumentsJSON: "{}"
        )

        let object = try resultObject(result)
        let returned = try #require(object["tasks"] as? [[String: Any]])
        #expect(returned.map { $0["id"] as? String } == ["running"])
    }

    @Test
    func getTaskRoutesTheRequestedIDAndReturnsTheTask() async throws {
        let task = makeTask(id: "task-2", status: "completed")
        let operations = TaskOperationsSpy(task: task)
        let router = RelayToolCallRouter(operations: operations)

        let result = await router.route(
            toolName: "relay_get_task",
            argumentsJSON: #"{"id":"task-2"}"#
        )

        #expect(result.success)
        let object = try resultObject(result)
        let resultTask = try #require(
            object["task"] as? [String: Any]
        )
        #expect(resultTask["id"] as? String == "task-2")
        #expect(resultTask["status"] as? String == "completed")

        let calls = await operations.recordedCalls()
        #expect(calls == [.get(id: "task-2")])
    }

    @Test
    func startTaskRoutesPromptAndWorkingDirectoryAndReturnsNewTask() async throws {
        let startedTask = makeTask(id: "task-new", status: "running")
        let operations = TaskOperationsSpy(startedTask: startedTask)
        let router = RelayToolCallRouter(operations: operations)

        let result = await router.route(
            toolName: "relay_start_task",
            argumentsJSON: """
                {"prompt":"Build the settings view","cwd":"/tmp"}
                """
        )

        #expect(result.success)
        let object = try resultObject(result)
        let resultTask = try #require(
            object["task"] as? [String: Any]
        )
        #expect(resultTask["id"] as? String == "task-new")

        let calls = await operations.recordedCalls()
        #expect(
            calls
                == [
                    .start(
                        prompt: "Build the settings view",
                        cwd: "/tmp"
                    ),
                ]
        )
    }

    @Test
    func startTaskWithoutWorkingDirectoryCreatesProjectlessTask() async throws {
        let operations = TaskOperationsSpy()
        let router = RelayToolCallRouter(operations: operations)

        let result = await router.route(
            toolName: "relay_start_task",
            argumentsJSON: #"{"prompt":"Change the system theme"}"#
        )

        #expect(result.success)
        #expect(
            await operations.recordedCalls()
                == [.start(prompt: "Change the system theme", cwd: nil)]
        )
    }

    @Test
    func interruptTaskRoutesTheIDAndReturnsAnAcknowledgement() async throws {
        let operations = TaskOperationsSpy()
        let router = RelayToolCallRouter(operations: operations)

        let result = await router.route(
            toolName: "relay_interrupt_task",
            argumentsJSON: #"{"id":"task-4"}"#
        )

        #expect(result.success)
        let object = try resultObject(result)
        #expect(object["ok"] as? Bool == true)
        #expect(object["taskId"] as? String == "task-4")
        #expect(object["message"] as? String == "Task interrupted.")

        let calls = await operations.recordedCalls()
        #expect(calls == [.interrupt(id: "task-4")])
    }

    @Test(
        arguments: [
            ("relay_get_recent_tasks", #"{"extra":true}"#),
            ("relay_get_running_tasks", #"{"extra":true}"#),
            ("relay_get_task", #"{"id":"task-1","extra":true}"#),
            (
                "relay_start_task",
                #"{"prompt":"Do work","cwd":"/Projects/Relay","extra":true}"#
            ),
            ("relay_interrupt_task", #"{"id":"task-1","extra":true}"#),
        ]
    )
    func everyRouteRejectsUndeclaredArguments(
        toolName: String,
        argumentsJSON: String
    ) async throws {
        let operations = TaskOperationsSpy(
            task: makeTask(id: "task-1")
        )
        let router = RelayToolCallRouter(operations: operations)

        let result = await router.route(
            toolName: toolName,
            argumentsJSON: argumentsJSON
        )

        #expect(!result.success)
        let object = try resultObject(result)
        let error = try #require(object["error"] as? [String: Any])
        #expect(error["code"] as? String == "invalid_arguments")
        #expect(
            (error["message"] as? String)?.contains("Unexpected argument")
                == true
        )

        let calls = await operations.recordedCalls()
        #expect(calls.isEmpty)
    }

    @Test(
        arguments: [
            (
                "relay_get_recent_tasks",
                "[]",
                "Expected arguments to be a JSON object."
            ),
            (
                "relay_get_task",
                #"{"id":42}"#,
                "Argument 'id' must be a string."
            ),
            (
                "relay_start_task",
                #"{"prompt":"   "}"#,
                "Argument 'prompt' must not be empty."
            ),
            (
                "relay_interrupt_task",
                "{broken",
                "Expected arguments to be a JSON object."
            ),
        ]
    )
    func malformedArgumentsReturnStructuredFailuresWithoutCallingOperations(
        toolName: String,
        argumentsJSON: String,
        expectedMessage: String
    ) async throws {
        let operations = TaskOperationsSpy()
        let router = RelayToolCallRouter(operations: operations)

        let result = await router.route(
            toolName: toolName,
            argumentsJSON: argumentsJSON
        )

        #expect(!result.success)
        let object = try resultObject(result)
        #expect(object["ok"] as? Bool == false)
        #expect(object["tool"] as? String == toolName)
        let error = try #require(object["error"] as? [String: Any])
        #expect(error["code"] as? String == "invalid_arguments")
        #expect(error["message"] as? String == expectedMessage)

        let calls = await operations.recordedCalls()
        #expect(calls.isEmpty)
    }

    @Test(arguments: [".", "Projects/Relay", "~/Work/Relay"])
    func startTaskRejectsNonAbsoluteWorkingDirectories(
        cwd: String
    ) async throws {
        let operations = TaskOperationsSpy()
        let router = RelayToolCallRouter(operations: operations)
        let arguments = try JSONSerialization.data(
            withJSONObject: ["prompt": "Do work", "cwd": cwd]
        )

        let result = await router.route(
            toolName: "relay_start_task",
            argumentsJSON: arguments
        )

        #expect(!result.success)
        let object = try resultObject(result)
        let error = try #require(object["error"] as? [String: Any])
        #expect(error["code"] as? String == "invalid_arguments")
        #expect(
            error["message"] as? String
                == "Argument 'cwd' must be an absolute path."
        )

        let calls = await operations.recordedCalls()
        #expect(calls.isEmpty)
    }

    @Test
    func startTaskRejectsAnAbsolutePathThatIsNotAnExistingDirectory() async throws {
        let operations = TaskOperationsSpy()
        let router = RelayToolCallRouter(operations: operations)
        let missing = "/relay-tests/missing-\(UUID().uuidString)"
        let arguments = try JSONSerialization.data(
            withJSONObject: ["prompt": "Do work", "cwd": missing]
        )

        let result = await router.route(
            toolName: "relay_start_task",
            argumentsJSON: arguments
        )

        #expect(!result.success)
        let object = try resultObject(result)
        let error = try #require(object["error"] as? [String: Any])
        #expect(error["code"] as? String == "invalid_arguments")
        #expect(
            error["message"] as? String
                == "Argument 'cwd' must be an existing directory."
        )
        #expect(await operations.recordedCalls().isEmpty)
    }

    @Test
    func unknownToolReturnsAStructuredFailure() async throws {
        let operations = TaskOperationsSpy()
        let router = RelayToolCallRouter(operations: operations)

        let result = await router.route(
            toolName: "relay_delete_task",
            argumentsJSON: "{}"
        )

        #expect(!result.success)
        let object = try resultObject(result)
        let error = try #require(object["error"] as? [String: Any])
        #expect(error["code"] as? String == "unknown_tool")

        let calls = await operations.recordedCalls()
        #expect(calls.isEmpty)
    }

    @Test
    func missingTaskReturnsAStructuredNotFoundFailure() async throws {
        let operations = TaskOperationsSpy(task: nil)
        let router = RelayToolCallRouter(operations: operations)

        let result = await router.route(
            toolName: "relay_get_task",
            argumentsJSON: #"{"id":"missing"}"#
        )

        #expect(!result.success)
        let object = try resultObject(result)
        let error = try #require(object["error"] as? [String: Any])
        #expect(error["code"] as? String == "task_not_found")
        #expect(
            (error["message"] as? String)?.contains("missing") == true
        )
    }

    @Test(
        arguments: [
            ("relay_get_recent_tasks", "{}"),
            ("relay_get_running_tasks", "{}"),
            ("relay_get_task", #"{"id":"task-1"}"#),
            (
                "relay_start_task",
                #"{"prompt":"Do work","cwd":"/tmp"}"#
            ),
            ("relay_interrupt_task", #"{"id":"task-1"}"#),
        ]
    )
    func operationErrorsBecomeStructuredToolFailures(
        toolName: String,
        argumentsJSON: String
    ) async throws {
        let operations = TaskOperationsSpy(shouldFail: true)
        let router = RelayToolCallRouter(operations: operations)

        let result = await router.route(
            toolName: toolName,
            argumentsJSON: argumentsJSON
        )

        #expect(!result.success)
        let object = try resultObject(result)
        let error = try #require(object["error"] as? [String: Any])
        #expect(error["code"] as? String == "operation_failed")
        #expect(error["message"] as? String == "The task operation failed.")
        #expect(!result.text.contains("Backend unavailable."))

        let calls = await operations.recordedCalls()
        #expect(calls.count == 1)
    }

    private func resultObject(
        _ result: RelayToolCallResult
    ) throws -> [String: Any] {
        try #require(
            JSONSerialization.jsonObject(with: Data(result.text.utf8))
                as? [String: Any]
        )
    }
}

private actor TaskOperationsSpy: RelayTaskOperations {
    enum Call: Sendable, Equatable {
        case list
        case get(id: String)
        case start(prompt: String, cwd: String?)
        case interrupt(id: String)
    }

    private let tasks: [RelayTaskSummary]
    private let task: RelayTaskSummary?
    private let startedTask: RelayTaskSummary
    private let shouldFail: Bool
    private var calls: [Call] = []

    init(
        tasks: [RelayTaskSummary] = [],
        task: RelayTaskSummary? = nil,
        startedTask: RelayTaskSummary = makeTask(id: "started-task"),
        shouldFail: Bool = false
    ) {
        self.tasks = tasks
        self.task = task
        self.startedTask = startedTask
        self.shouldFail = shouldFail
    }

    func listTasks() async throws -> [RelayTaskSummary] {
        calls.append(.list)
        try failIfRequested()
        return tasks
    }

    func getTask(id: String) async throws -> RelayTaskSummary? {
        calls.append(.get(id: id))
        try failIfRequested()
        return task
    }

    func startTask(
        prompt: String,
        cwd: String?
    ) async throws -> RelayTaskSummary {
        calls.append(.start(prompt: prompt, cwd: cwd))
        try failIfRequested()
        return startedTask
    }

    func interruptTask(id: String) async throws {
        calls.append(.interrupt(id: id))
        try failIfRequested()
    }

    func recordedCalls() -> [Call] {
        calls
    }

    private func failIfRequested() throws {
        if shouldFail {
            throw TaskOperationsSpyError.backendUnavailable
        }
    }
}

private enum TaskOperationsSpyError: LocalizedError {
    case backendUnavailable

    var errorDescription: String? {
        "Backend unavailable."
    }
}

private func makeTask(
    id: String,
    status: String = "idle",
    updatedAt: Date = Date(timeIntervalSince1970: 1_721_234_567)
) -> RelayTaskSummary {
    RelayTaskSummary(
        id: id,
        title: "Task \(id)",
        project: "/Projects/Relay",
        status: status,
        updatedAt: updatedAt
    )
}
