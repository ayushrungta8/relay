import Foundation

public struct RelayToolCallResult: Sendable, Equatable, Encodable {
    public let success: Bool
    public let text: String

    public init(success: Bool, text: String) {
        self.success = success
        self.text = text
    }
}

public actor RelayToolCallRouter {
    private let operations: any RelayTaskOperations
    private let supervision: any RelaySupervisionStateReading

    public init(operations: any RelayTaskOperations) {
        self.operations = operations
        supervision = EmptySupervisionState()
    }

    public init(
        operations: any RelayTaskOperations,
        supervision: any RelaySupervisionStateReading
    ) {
        self.operations = operations
        self.supervision = supervision
    }

    public func route(
        toolName: String,
        argumentsJSON: String
    ) async -> RelayToolCallResult {
        await route(
            toolName: toolName,
            argumentsJSON: Data(argumentsJSON.utf8)
        )
    }

    public func route(
        toolName: String,
        argumentsJSON: Data
    ) async -> RelayToolCallResult {
        guard let tool = RelayDynamicToolName(rawValue: toolName) else {
            return failure(
                toolName: toolName,
                code: "unknown_tool",
                message: "Unknown Relay tool '\(toolName)'."
            )
        }

        do {
            switch tool {
            case .listTasks:
                _ = try validatedArguments(
                    from: argumentsJSON,
                    allowedKeys: []
                )
                let tasks = try await operations.listTasks()
                return success(
                    TasksPayload(
                        ok: true,
                        tool: toolName,
                        tasks: tasks
                    )
                )
            case .getTask:
                let arguments = try validatedArguments(
                    from: argumentsJSON,
                    allowedKeys: ["id"]
                )
                let id: String
                if arguments["id"] != nil {
                    id = try requiredString("id", in: arguments)
                } else if let contextualID = await supervision
                    .taskReferenceContext().resolvedTaskID {
                    id = contextualID
                } else {
                    return failure(
                        toolName: toolName,
                        code: "clarification_required",
                        message: "Which task do you mean? Select a task or name it."
                    )
                }
                guard let task = try await operations.getTask(id: id) else {
                    return failure(
                        toolName: toolName,
                        code: "task_not_found",
                        message: "No visible task has id '\(id)'."
                    )
                }
                return success(
                    TaskPayload(ok: true, tool: toolName, task: task)
                )
            case .getAttentionInbox:
                _ = try validatedArguments(
                    from: argumentsJSON,
                    allowedKeys: []
                )
                return success(
                    TasksPayload(
                        ok: true,
                        tool: toolName,
                        tasks: await supervision.attentionInbox()
                    )
                )
            case .getUsage:
                _ = try validatedArguments(
                    from: argumentsJSON,
                    allowedKeys: []
                )
                return success(
                    UsagePayload(
                        ok: true,
                        tool: toolName,
                        usage: await supervision.currentUsage()
                    )
                )
            case .startTask:
                let arguments = try validatedArguments(
                    from: argumentsJSON,
                    allowedKeys: ["prompt", "cwd"]
                )
                let prompt = try requiredString("prompt", in: arguments)
                let cwd = try requiredAbsolutePath("cwd", in: arguments)
                let task = try await operations.startTask(
                    prompt: prompt,
                    cwd: cwd
                )
                return success(
                    TaskPayload(ok: true, tool: toolName, task: task)
                )
            case .sendToTask:
                let arguments = try validatedArguments(
                    from: argumentsJSON,
                    allowedKeys: ["id", "prompt"]
                )
                let id = try requiredString("id", in: arguments)
                let prompt = try requiredString("prompt", in: arguments)
                try await operations.sendToTask(id: id, prompt: prompt)
                return success(
                    ActionPayload(
                        ok: true,
                        tool: toolName,
                        taskId: id,
                        message: "Prompt sent to task."
                    )
                )
            case .interruptTask:
                let arguments = try validatedArguments(
                    from: argumentsJSON,
                    allowedKeys: ["id"]
                )
                let id = try requiredString("id", in: arguments)
                try await operations.interruptTask(id: id)
                return success(
                    ActionPayload(
                        ok: true,
                        tool: toolName,
                        taskId: id,
                        message: "Task interrupted."
                    )
                )
            }
        } catch let error as ArgumentValidationError {
            return failure(
                toolName: toolName,
                code: "invalid_arguments",
                message: error.message
            )
        } catch {
            return failure(
                toolName: toolName,
                code: "operation_failed",
                message: "The task operation failed."
            )
        }
    }

    private func success<Payload: Encodable>(
        _ payload: Payload
    ) -> RelayToolCallResult {
        RelayToolCallResult(success: true, text: encode(payload))
    }

    private func failure(
        toolName: String,
        code: String,
        message: String
    ) -> RelayToolCallResult {
        RelayToolCallResult(
            success: false,
            text: encode(
                FailurePayload(
                    ok: false,
                    tool: toolName,
                    error: FailureDetail(code: code, message: message)
                )
            )
        )
    }

    private func encode<Payload: Encodable>(_ payload: Payload) -> String {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys]

        guard
            let data = try? encoder.encode(payload),
            let text = String(data: data, encoding: .utf8)
        else {
            return """
                {"error":{"code":"encoding_failed","message":"Relay could not \
                encode the tool result."},"ok":false}
                """
        }

        return text
    }

    private func validatedArguments(
        from data: Data,
        allowedKeys: Set<String>
    ) throws -> [String: Any] {
        guard
            let object = try? JSONSerialization.jsonObject(
                with: data,
                options: [.fragmentsAllowed]
            ),
            let arguments = object as? [String: Any]
        else {
            throw ArgumentValidationError(
                message: "Expected arguments to be a JSON object."
            )
        }

        let unexpectedKeys = Set(arguments.keys)
            .subtracting(allowedKeys)
            .sorted()
        if !unexpectedKeys.isEmpty {
            let names = unexpectedKeys
                .map { "'\($0)'" }
                .joined(separator: ", ")
            let noun = unexpectedKeys.count == 1
                ? "argument"
                : "arguments"
            throw ArgumentValidationError(
                message: "Unexpected \(noun): \(names)."
            )
        }

        return arguments
    }

    private func requiredString(
        _ key: String,
        in arguments: [String: Any]
    ) throws -> String {
        guard let value = arguments[key] else {
            throw ArgumentValidationError(
                message: "Missing required argument '\(key)'."
            )
        }
        guard let string = value as? String else {
            throw ArgumentValidationError(
                message: "Argument '\(key)' must be a string."
            )
        }
        guard !string.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        else {
            throw ArgumentValidationError(
                message: "Argument '\(key)' must not be empty."
            )
        }

        return string
    }

    private func requiredAbsolutePath(
        _ key: String,
        in arguments: [String: Any]
    ) throws -> String {
        let path = try requiredString(key, in: arguments)
        guard path.hasPrefix("/") else {
            throw ArgumentValidationError(
                message: "Argument '\(key)' must be an absolute path."
            )
        }

        return path
    }
}

private struct TasksPayload: Encodable {
    let ok: Bool
    let tool: String
    let tasks: [RelayTaskSummary]
}

private struct TaskPayload: Encodable {
    let ok: Bool
    let tool: String
    let task: RelayTaskSummary
}

private struct UsagePayload: Encodable {
    let ok: Bool
    let tool: String
    let usage: RelayControllerUsage?
}

private struct ActionPayload: Encodable {
    let ok: Bool
    let tool: String
    let taskId: String
    let message: String
}

private struct FailurePayload: Encodable {
    let ok: Bool
    let tool: String
    let error: FailureDetail
}

private struct FailureDetail: Encodable {
    let code: String
    let message: String
}

private struct ArgumentValidationError: Error {
    let message: String
}

private struct EmptySupervisionState: RelaySupervisionStateReading {
    func attentionInbox() async -> [RelayTaskSummary] { [] }
    func currentUsage() async -> RelayControllerUsage? { nil }
    func taskReferenceContext() async -> RelayTaskReferenceContext { .init() }
}
