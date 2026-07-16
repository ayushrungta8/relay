import Foundation

public struct RelayControllerConfiguration: Sendable, Equatable {
    public let developerInstructions: String
    public let dynamicTools: [RelayDynamicToolDefinition]

    public init(
        developerInstructions: String,
        dynamicTools: [RelayDynamicToolDefinition]
    ) {
        self.developerInstructions = developerInstructions
        self.dynamicTools = dynamicTools
    }

    public static let `default` = RelayControllerConfiguration(
        developerInstructions: RelayControllerInstructions.developer,
        dynamicTools: RelayDynamicTools.definitions
    )
}

public struct RelayControllerThread: Sendable, Equatable {
    public let id: String

    public init(id: String) {
        self.id = id
    }
}

public struct RelayControllerToolCall: Sendable, Equatable {
    public let id: String
    public let toolName: String
    public let argumentsJSON: Data

    public init(id: String, toolName: String, argumentsJSON: Data) {
        self.id = id
        self.toolName = toolName
        self.argumentsJSON = argumentsJSON
    }
}

public enum RelayControllerEvent: Sendable, Equatable {
    case dynamicToolCall(RelayControllerToolCall)
    case finalText(String)
}

public protocol RelayControllerSession: Sendable {
    func ensureControllerThread(
        configuration: RelayControllerConfiguration
    ) async throws -> RelayControllerThread

    func submitUserText(
        _ text: String,
        to controller: RelayControllerThread
    ) async throws -> AsyncThrowingStream<RelayControllerEvent, any Error>

    func completeToolCall(
        _ call: RelayControllerToolCall,
        with result: RelayToolCallResult
    ) async throws
}

public enum RelayControllerInstructions {
    public static let developer = """
        You are Relay's persistent controller and liaison between the user and \
        visible Codex worker tasks. You are the single entry point for every \
        typed or spoken user message.

        You may answer conversational, factual, and task-status questions \
        directly when the answer is already known from the conversation or \
        task tools. For current task state, call relay_list_tasks or \
        relay_get_task and never guess. When the user asks what a worker is \
        doing, whether it is going well, or what changed, list tasks first and \
        then call relay_get_task for each relevant worker; active or idle \
        status alone is not a progress report.

        You must delegate any request that requires doing work, including \
        implementation, debugging, editing, investigation, research, or \
        multi-step execution. You must not do worker work yourself.

        Before delegating, inspect visible task state. If an existing task \
        already owns the same project and work, use relay_send_to_task to steer \
        it. Otherwise use relay_start_task with a complete prompt and the \
        correct working directory. Use relay_interrupt_task only when the user \
        asks to stop or cancel work, or when continuing would be harmful.

        Never claim delegated work is complete until the worker task reports \
        that outcome. After a successful delegation, acknowledge it succinctly \
        in one short sentence that identifies the task or action. If a task \
        tool fails, say so plainly and do not pretend the delegation succeeded.
        """
}
