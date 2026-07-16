import Foundation

public enum RelayDynamicToolName: String, CaseIterable, Sendable {
    case listTasks = "relay_list_tasks"
    case getTask = "relay_get_task"
    case startTask = "relay_start_task"
    case sendToTask = "relay_send_to_task"
    case interruptTask = "relay_interrupt_task"
}

public struct RelayDynamicToolDefinition: Sendable, Equatable, Encodable {
    public let type: String
    public let name: String
    public let description: String
    public let inputSchema: RelayJSONSchema

    public init(
        name: String,
        description: String,
        inputSchema: RelayJSONSchema
    ) {
        type = "function"
        self.name = name
        self.description = description
        self.inputSchema = inputSchema
    }
}

public struct RelayJSONSchema: Sendable, Equatable, Encodable {
    public let type: String
    public let properties: [String: RelayJSONSchemaProperty]
    public let required: [String]
    public let additionalProperties: Bool

    public init(
        properties: [String: RelayJSONSchemaProperty],
        required: [String]
    ) {
        type = "object"
        self.properties = properties
        self.required = required
        additionalProperties = false
    }
}

public struct RelayJSONSchemaProperty: Sendable, Equatable, Encodable {
    public let type: String
    public let description: String

    public init(type: String = "string", description: String) {
        self.type = type
        self.description = description
    }
}

public enum RelayDynamicTools {
    public static let definitions: [RelayDynamicToolDefinition] = [
        RelayDynamicToolDefinition(
            name: RelayDynamicToolName.listTasks.rawValue,
            description: """
            List visible Codex worker tasks and their current status. Use this \
            before answering task-status questions or deciding whether \
            existing work should be steered.
            """,
            inputSchema: RelayJSONSchema(properties: [:], required: [])
        ),
        RelayDynamicToolDefinition(
            name: RelayDynamicToolName.getTask.rawValue,
            description: """
            Get one visible Codex worker task by its exact id, including its \
            title, project, status, last update time, and most recent worker \
            progress message when available.
            """,
            inputSchema: RelayJSONSchema(
                properties: [
                    "id": RelayJSONSchemaProperty(
                        description: "The exact id of the worker task to inspect."
                    ),
                ],
                required: ["id"]
            )
        ),
        RelayDynamicToolDefinition(
            name: RelayDynamicToolName.startTask.rawValue,
            description: """
            Start a new visible Codex worker task for work that is not already \
            covered by an existing task. The worker, not the controller, \
            performs the work.
            """,
            inputSchema: RelayJSONSchema(
                properties: [
                    "prompt": RelayJSONSchemaProperty(
                        description: """
                        Complete instructions for the worker, including the \
                        requested outcome and relevant context.
                        """
                    ),
                    "cwd": RelayJSONSchemaProperty(
                        description: """
                        Absolute working-directory path for the worker task.
                        """
                    ),
                ],
                required: ["prompt", "cwd"]
            )
        ),
        RelayDynamicToolDefinition(
            name: RelayDynamicToolName.sendToTask.rawValue,
            description: """
            Send follow-up instructions to an existing visible Codex worker \
            task. Use this to steer matching work instead of starting a \
            duplicate task.
            """,
            inputSchema: RelayJSONSchema(
                properties: [
                    "id": RelayJSONSchemaProperty(
                        description: "The exact id of the worker task to steer."
                    ),
                    "prompt": RelayJSONSchemaProperty(
                        description: """
                        The new instruction or context to send to the worker.
                        """
                    ),
                ],
                required: ["id", "prompt"]
            )
        ),
        RelayDynamicToolDefinition(
            name: RelayDynamicToolName.interruptTask.rawValue,
            description: """
            Interrupt an existing visible Codex worker task. Use only when the \
            user asks to stop or cancel it, or when continuing would be harmful.
            """,
            inputSchema: RelayJSONSchema(
                properties: [
                    "id": RelayJSONSchemaProperty(
                        description: "The exact id of the worker task to interrupt."
                    ),
                ],
                required: ["id"]
            )
        ),
    ]
}
