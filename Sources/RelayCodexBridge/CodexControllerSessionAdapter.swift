import Foundation
import RelayBrain
import RelayCodexClient

public enum CodexControllerSessionError: Error, Sendable, Equatable {
    case emptyCommand
    case submissionInProgress
    case malformedResponse(String)
    case turnFailed(String)
    case turnInterrupted
    case noControllerAnswer
    case unknownToolCall(String)
}

extension CodexControllerSessionError: LocalizedError {
    public var errorDescription: String? {
        switch self {
        case .emptyCommand:
            "Relay cannot send an empty command."
        case .submissionInProgress:
            "Relay is already handling a command."
        case let .malformedResponse(method):
            "Codex returned an invalid response for \(method)."
        case let .turnFailed(message):
            "The Relay controller failed: \(message)"
        case .turnInterrupted:
            "The Relay controller was interrupted."
        case .noControllerAnswer:
            "The Relay controller completed without an answer."
        case let .unknownToolCall(id):
            "Relay no longer has the pending tool call \(id)."
        }
    }
}

public actor CodexControllerSessionAdapter: RelayControllerSession {
    private let rpc: any CodexSessionRPC
    private let identity: RelayControllerIdentity
    private let cwd: String

    private var isStarted = false
    private var eventTask: Task<Void, Never>?
    private var cachedController: RelayControllerThread?
    private var controllerConfiguration: RelayControllerConfiguration?
    private var activeTurn: ActiveControllerTurn?
    private var toolRequestIDs: [String: JSONRPCRequestID] = [:]

    public init(
        rpc: any CodexSessionRPC,
        store: any RelayControllerThreadStoring,
        cwd: String
    ) {
        self.rpc = rpc
        identity = RelayControllerIdentity(store: store)
        self.cwd = cwd
    }

    public init(
        rpc: any CodexSessionRPC,
        identity: RelayControllerIdentity,
        cwd: String
    ) {
        self.rpc = rpc
        self.identity = identity
        self.cwd = cwd
    }

    deinit {
        eventTask?.cancel()
    }

    public func ensureControllerThread(
        configuration: RelayControllerConfiguration
    ) async throws -> RelayControllerThread {
        try await ensureRPCStarted()
        controllerConfiguration = configuration

        if let cachedController {
            return cachedController
        }

        if let storedID = await identity.recoverThreadID(),
           let resumed = await resumeStoredController(
               id: storedID,
               configuration: configuration
           ) {
            cachedController = resumed
            await identity.activate(threadID: resumed.id)
            await nameControllerThread(id: resumed.id)
            return resumed
        }
        if let staleID = await identity.currentThreadID() {
            await identity.discard(threadID: staleID)
        }

        let tools = try encodeAsJSONValue(configuration.dynamicTools)
        let response = try await rpc.requestJSON(
            method: "thread/start",
            params: .object([
                "approvalPolicy": .string("never"),
                "cwd": .string(cwd),
                "developerInstructions": .string(
                    configuration.developerInstructions
                ),
                "dynamicTools": tools,
                "ephemeral": .bool(false),
                "model": .string(configuration.model),
                "sandbox": .string("read-only"),
            ]),
            timeout: .seconds(15)
        )
        guard let id = response["thread"]?["id"]?.stringValue else {
            throw CodexControllerSessionError.malformedResponse(
                "thread/start"
            )
        }

        let controller = RelayControllerThread(id: id)
        await identity.activate(threadID: id)
        cachedController = controller
        await nameControllerThread(id: id)
        return controller
    }

    public func submitUserText(
        _ text: String,
        to controller: RelayControllerThread
    ) async throws -> AsyncThrowingStream<RelayControllerEvent, any Error> {
        let command = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !command.isEmpty else {
            throw CodexControllerSessionError.emptyCommand
        }
        guard activeTurn == nil else {
            throw CodexControllerSessionError.submissionInProgress
        }
        try await ensureRPCStarted()
        let configuration = controllerConfiguration ?? .default

        let pair = AsyncThrowingStream<RelayControllerEvent, any Error>
            .makeStream(bufferingPolicy: .unbounded)
        activeTurn = ActiveControllerTurn(
            threadID: controller.id,
            turnID: nil,
            accumulatedText: "",
            finalAnswerMessageIDs: [],
            continuation: pair.continuation
        )

        do {
            let response = try await rpc.requestJSON(
                method: "turn/start",
                params: .object([
                    "threadId": .string(controller.id),
                    "input": Self.textInput(command),
                    "model": .string(configuration.model),
                    "effort": .string(configuration.reasoningEffort),
                ]),
                timeout: .seconds(15)
            )
            guard let turnID = response["turn"]?["id"]?.stringValue else {
                throw CodexControllerSessionError.malformedResponse(
                    "turn/start"
                )
            }
            activeTurn?.turnID = turnID
            return pair.stream
        } catch {
            activeTurn?.continuation.finish(throwing: error)
            activeTurn = nil
            throw error
        }
    }

    public func completeToolCall(
        _ call: RelayControllerToolCall,
        with result: RelayToolCallResult
    ) async throws {
        guard let requestID = toolRequestIDs.removeValue(forKey: call.id) else {
            throw CodexControllerSessionError.unknownToolCall(call.id)
        }

        try await rpc.respond(
            to: requestID,
            result: .object([
                "success": .bool(result.success),
                "contentItems": .array([
                    .object([
                        "type": .string("inputText"),
                        "text": .string(result.text),
                    ]),
                ]),
            ])
        )
    }

    public func stop() async {
        eventTask?.cancel()
        eventTask = nil
        activeTurn?.continuation.finish(
            throwing: CodexClientError.transportClosed
        )
        activeTurn = nil
        toolRequestIDs.removeAll()
        await rpc.stop()
        isStarted = false
    }

    private func ensureRPCStarted() async throws {
        guard !isStarted else { return }
        try await rpc.start()
        isStarted = true

        let events = rpc.events
        eventTask = Task { [weak self] in
            for await event in events {
                guard !Task.isCancelled else { return }
                await self?.handle(event)
            }
        }
    }

    private func resumeStoredController(
        id: String,
        configuration: RelayControllerConfiguration
    ) async -> RelayControllerThread? {
        guard
            let response = try? await rpc.requestJSON(
                method: "thread/resume",
                params: .object([
                    "threadId": .string(id),
                    "excludeTurns": .bool(true),
                    "cwd": .string(cwd),
                    "developerInstructions": .string(
                        configuration.developerInstructions
                    ),
                    "approvalPolicy": .string("never"),
                    "model": .string(configuration.model),
                    "sandbox": .string("read-only"),
                ]),
                timeout: .seconds(15)
            ),
            response["thread"]?["id"]?.stringValue == id
        else {
            return nil
        }
        return RelayControllerThread(id: id)
    }

    private func nameControllerThread(id: String) async {
        let _: JSONValue? = try? await rpc.requestJSON(
            method: "thread/name/set",
            params: .object([
                "threadId": .string(id),
                "name": .string("Relay Controller"),
            ]),
            timeout: .seconds(8)
        )
    }

    private func handle(_ event: CodexServerEvent) async {
        switch event {
        case let .serverRequest(request):
            await handle(request)
        case let .notification(method, params):
            handleNotification(method: method, params: params)
        case let .lifecycle(state):
            if case let .failed(message) = state {
                failActiveTurn(
                    CodexControllerSessionError.turnFailed(message)
                )
            }
        case let .protocolIssue(message):
            failActiveTurn(
                CodexControllerSessionError.turnFailed(message)
            )
        }
    }

    private func handle(_ request: CodexServerRequest) async {
        if request.method == "item/tool/call",
           let params = request.params?.objectValue,
           matchesActiveTurn(params),
           let callID = params["callId"]?.stringValue,
           let toolName = params["tool"]?.stringValue,
           let arguments = params["arguments"],
           let argumentsData = try? JSONEncoder().encode(arguments) {
            adoptTurnID(from: params)
            toolRequestIDs[callID] = request.id
            activeTurn?.continuation.yield(
                .dynamicToolCall(
                    RelayControllerToolCall(
                        id: callID,
                        toolName: toolName,
                        argumentsJSON: argumentsData
                    )
                )
            )
            return
        }

        guard let controllerID = await identity.currentThreadID(),
              Self.requestThreadID(request) == controllerID,
              let result = Self.safeAutomaticResponse(
            to: request.method
        ) else {
            return
        }
        try? await rpc.respond(to: request.id, result: result)
    }

    private static func safeAutomaticResponse(
        to method: String
    ) -> JSONValue? {
        switch method {
        case "item/commandExecution/requestApproval",
             "item/fileChange/requestApproval":
            .object(["decision": .string("decline")])

        case "item/permissions/requestApproval":
            .object([
                "permissions": .object([:]),
                "scope": .string("turn"),
            ])

        case "item/tool/requestUserInput":
            .object(["answers": .object([:])])

        case "mcpServer/elicitation/request":
            .object([
                "action": .string("decline"),
                "content": .null,
            ])

        case "applyPatchApproval", "execCommandApproval":
            .object(["decision": .string("denied")])

        case "item/tool/call":
            .object([
                "success": .bool(false),
                "contentItems": .array([
                    .object([
                        "type": .string("inputText"),
                        "text": .string(
                            "This dynamic tool is not available in Relay."
                        ),
                    ]),
                ]),
            ])

        default:
            nil
        }
    }

    private static func requestThreadID(
        _ request: CodexServerRequest
    ) -> String? {
        request.params?["threadId"]?.stringValue
            ?? request.params?["conversationId"]?.stringValue
    }

    private func handleNotification(
        method: String,
        params: JSONValue?
    ) {
        guard let params = params?.objectValue,
              matchesActiveTurn(params) else {
            return
        }

        adoptTurnID(from: params)
        switch method {
        case "item/started":
            guard let item = params["item"]?.objectValue,
                  item["type"]?.stringValue == "agentMessage",
                  item["phase"]?.stringValue == "final_answer",
                  let itemID = item["id"]?.stringValue else {
                return
            }
            activeTurn?.finalAnswerMessageIDs.insert(itemID)
        case "item/agentMessage/delta":
            if let itemID = params["itemId"]?.stringValue,
               activeTurn?.finalAnswerMessageIDs.contains(itemID) == true,
               let delta = params["delta"]?.stringValue {
                activeTurn?.accumulatedText += delta
                activeTurn?.continuation.yield(.textDelta(delta))
            }
        case "turn/completed":
            completeActiveTurn(params: params)
        default:
            break
        }
    }

    private func matchesActiveTurn(
        _ params: [String: JSONValue]
    ) -> Bool {
        guard let activeTurn,
              params["threadId"]?.stringValue == activeTurn.threadID else {
            return false
        }

        let eventTurnID =
            params["turnId"]?.stringValue
            ?? params["turn"]?["id"]?.stringValue
        guard let expectedTurnID = activeTurn.turnID else {
            return true
        }
        return eventTurnID == expectedTurnID
    }

    private func adoptTurnID(
        from params: [String: JSONValue]
    ) {
        guard activeTurn?.turnID == nil else { return }
        activeTurn?.turnID =
            params["turnId"]?.stringValue
            ?? params["turn"]?["id"]?.stringValue
    }

    private func completeActiveTurn(
        params: [String: JSONValue]
    ) {
        guard let turn = params["turn"]?.objectValue,
              let status = turn["status"]?.stringValue else {
            failActiveTurn(
                CodexControllerSessionError.malformedResponse(
                    "turn/completed"
                )
            )
            return
        }

        switch status {
        case "completed":
            let answer = finalAnswer(in: turn)
                ?? activeTurn?.accumulatedText
            let normalized = answer?.trimmingCharacters(
                in: .whitespacesAndNewlines
            )
            guard let normalized, !normalized.isEmpty else {
                failActiveTurn(
                    CodexControllerSessionError.noControllerAnswer
                )
                return
            }
            activeTurn?.continuation.yield(.finalText(normalized))
            finishActiveTurn()
        case "interrupted":
            failActiveTurn(
                CodexControllerSessionError.turnInterrupted
            )
        case "failed":
            let message = turn["error"]?["message"]?.stringValue
                ?? "Unknown Codex error."
            failActiveTurn(
                CodexControllerSessionError.turnFailed(message)
            )
        default:
            failActiveTurn(
                CodexControllerSessionError.malformedResponse(
                    "turn/completed"
                )
            )
        }
    }

    private func finalAnswer(
        in turn: [String: JSONValue]
    ) -> String? {
        let messages = turn["items"]?.arrayValue?.compactMap { item -> (
            phase: String?,
            text: String
        )? in
            guard item["type"]?.stringValue == "agentMessage",
                  let text = item["text"]?.stringValue else {
                return nil
            }
            return (item["phase"]?.stringValue, text)
        } ?? []

        return messages.last { $0.phase == "final_answer" }?.text
            ?? messages.last?.text
    }

    private func finishActiveTurn() {
        activeTurn?.continuation.finish()
        activeTurn = nil
        toolRequestIDs.removeAll()
    }

    private func failActiveTurn(_ error: any Error) {
        activeTurn?.continuation.finish(throwing: error)
        activeTurn = nil
        toolRequestIDs.removeAll()
    }

    private func encodeAsJSONValue<Value: Encodable>(
        _ value: Value
    ) throws -> JSONValue {
        let data = try JSONEncoder().encode(value)
        return try JSONDecoder().decode(JSONValue.self, from: data)
    }

    private static func textInput(_ text: String) -> JSONValue {
        .array([
            .object([
                "type": .string("text"),
                "text": .string(text),
            ]),
        ])
    }

}

private struct ActiveControllerTurn {
    let threadID: String
    var turnID: String?
    var accumulatedText: String
    var finalAnswerMessageIDs: Set<String>
    let continuation:
        AsyncThrowingStream<RelayControllerEvent, any Error>.Continuation
}
