import Foundation
import Testing
@testable import RelayBrain

struct RelayAttentionToolTests {
    @Test
    func taskStatusReadsUseTheEnrichedSupervisionSnapshot() async throws {
        let now = Date(timeIntervalSince1970: 1_784_210_400)
        let operations = SupervisionTaskOperationsStub(
            tasksByID: [
                "worker": makeTask(id: "worker", status: "notLoaded"),
            ]
        )
        let router = RelayToolCallRouter(
            operations: operations,
            supervision: SupervisionStateStub(
                visible: [makeTask(id: "worker", status: "running")],
                context: RelayTaskReferenceContext(
                    selectedTaskID: "worker"
                )
            ),
            now: { now }
        )

        let list = await router.route(
            toolName: "relay_get_recent_tasks",
            argumentsJSON: "{}"
        )
        let listedTasks = try #require(
            try resultObject(list)["tasks"] as? [[String: Any]]
        )
        #expect(listedTasks.first?["status"] as? String == "running")
        #expect(
            try resultObject(list)["focusedTaskId"] as? String == "worker"
        )

        let get = await router.route(
            toolName: "relay_get_task",
            argumentsJSON: #"{"id":"worker"}"#
        )
        let task = try #require(
            try resultObject(get)["task"] as? [String: Any]
        )
        #expect(task["status"] as? String == "running")
    }

    @Test
    func attentionInboxReturnsCurrentWaitingTasks() async throws {
        let now = Date(timeIntervalSince1970: 1_784_210_400)
        let state = SupervisionStateStub(
            attention: [makeTask(id: "needs-user", status: "needsInput")]
        )
        let router = RelayToolCallRouter(
            operations: SupervisionTaskOperationsStub(),
            supervision: state,
            now: { now }
        )

        let result = await router.route(
            toolName: "relay_get_attention_inbox",
            argumentsJSON: "{}"
        )

        #expect(result.success)
        let object = try resultObject(result)
        let tasks = try #require(object["tasks"] as? [[String: Any]])
        #expect(tasks.map { $0["id"] as? String } == ["needs-user"])
        #expect(tasks.first?["status"] as? String == "needsInput")
    }

    @Test
    func usageReturnsCurrentCapacityWithoutInventingMissingWindows() async throws {
        let state = SupervisionStateStub(
            usage: RelayControllerUsage(
                limitID: "codex",
                limitName: "Codex",
                primary: RelayControllerUsageWindow(
                    usedPercent: 64,
                    windowDurationMinutes: 300,
                    resetsAt: 1_784_220_000
                ),
                secondary: nil,
                resetCreditsAvailableCount: 2
            )
        )
        let router = RelayToolCallRouter(
            operations: SupervisionTaskOperationsStub(),
            supervision: state
        )

        let result = await router.route(
            toolName: "relay_get_usage",
            argumentsJSON: "{}"
        )

        #expect(result.success)
        let object = try resultObject(result)
        let usage = try #require(object["usage"] as? [String: Any])
        let primary = try #require(usage["primary"] as? [String: Any])
        #expect(primary["usedPercent"] as? Int == 64)
        #expect(primary["windowDurationMinutes"] as? Int == 300)
        #expect(usage["secondary"] is NSNull)
        #expect(usage["resetCreditsAvailableCount"] as? Int == 2)
    }

    @Test
    func contextualGetTaskPrefersSelectedThenMostRecentlyInteracted() async throws {
        let operations = SupervisionTaskOperationsStub(
            tasksByID: [
                "selected": makeTask(id: "selected"),
                "recent": makeTask(id: "recent"),
            ]
        )
        let selectedRouter = RelayToolCallRouter(
            operations: operations,
            supervision: SupervisionStateStub(
                context: RelayTaskReferenceContext(
                    selectedTaskID: "selected",
                    lastInteractedTaskID: "recent"
                )
            )
        )

        let selected = await selectedRouter.route(
            toolName: "relay_get_task",
            argumentsJSON: "{}"
        )
        #expect(try taskID(in: selected) == "selected")

        let recentRouter = RelayToolCallRouter(
            operations: operations,
            supervision: SupervisionStateStub(
                context: RelayTaskReferenceContext(
                    selectedTaskID: nil,
                    lastInteractedTaskID: "recent"
                )
            )
        )
        let recent = await recentRouter.route(
            toolName: "relay_get_task",
            argumentsJSON: "{}"
        )
        #expect(try taskID(in: recent) == "recent")
    }

    @Test
    func contextualGetTaskAsksForClarificationWhenThereIsNoContext() async throws {
        let router = RelayToolCallRouter(
            operations: SupervisionTaskOperationsStub(),
            supervision: SupervisionStateStub()
        )

        let result = await router.route(
            toolName: "relay_get_task",
            argumentsJSON: "{}"
        )

        #expect(!result.success)
        let object = try resultObject(result)
        let error = try #require(object["error"] as? [String: Any])
        #expect(error["code"] as? String == "clarification_required")
        #expect(
            error["message"] as? String
                == "Which task do you mean? Select a task or name it."
        )
    }

    private func taskID(in result: RelayToolCallResult) throws -> String? {
        let object = try resultObject(result)
        return (object["task"] as? [String: Any])?["id"] as? String
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

private actor SupervisionTaskOperationsStub: RelayTaskOperations {
    private let tasksByID: [String: RelayTaskSummary]

    init(tasksByID: [String: RelayTaskSummary] = [:]) {
        self.tasksByID = tasksByID
    }

    func listTasks() async throws -> [RelayTaskSummary] {
        Array(tasksByID.values)
    }

    func getTask(id: String) async throws -> RelayTaskSummary? {
        tasksByID[id]
    }

    func startTask(prompt: String, cwd: String) async throws -> RelayTaskSummary {
        makeTask(id: "started")
    }

    func sendToTask(id: String, prompt: String) async throws {}
    func interruptTask(id: String) async throws {}
}

private struct SupervisionStateStub: RelaySupervisionStateReading {
    let visible: [RelayTaskSummary]?
    let attention: [RelayTaskSummary]
    let usage: RelayControllerUsage?
    let context: RelayTaskReferenceContext

    init(
        visible: [RelayTaskSummary]? = nil,
        attention: [RelayTaskSummary] = [],
        usage: RelayControllerUsage? = nil,
        context: RelayTaskReferenceContext = .init()
    ) {
        self.visible = visible
        self.attention = attention
        self.usage = usage
        self.context = context
    }

    func visibleTasks() async -> [RelayTaskSummary]? { visible }
    func attentionInbox() async -> [RelayTaskSummary] { attention }
    func currentUsage() async -> RelayControllerUsage? { usage }
    func taskReferenceContext() async -> RelayTaskReferenceContext { context }
}

private func makeTask(
    id: String,
    status: String = "idle"
) -> RelayTaskSummary {
    RelayTaskSummary(
        id: id,
        title: "Task \(id)",
        project: "/Projects/Relay",
        status: status,
        updatedAt: Date(timeIntervalSince1970: 1_784_210_400)
    )
}
