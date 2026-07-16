import Foundation
import RelayBrain
import RelayCodexClient
import RelayCore

public enum RelayPendingInteractionBrokerError:
    Error,
    Sendable,
    Equatable
{
    case unknownInteraction(String)
    case wrongInteractionKind
    case unsupportedDecision
    case incompleteAnswers
}

extension RelayPendingInteractionBrokerError: LocalizedError {
    public var errorDescription: String? {
        switch self {
        case let .unknownInteraction(id):
            "Relay no longer owns pending request \(id)."
        case .wrongInteractionKind:
            "That response does not match the pending request."
        case .unsupportedDecision:
            "That decision is not supported by this Codex request."
        case .incompleteAnswers:
            "Answer every question before submitting."
        }
    }
}

public actor RelayPendingInteractionBroker {
    public nonisolated let updates: AsyncStream<[RelayPendingInteraction]>

    private let rpc: any CodexSessionRPC
    private let controllerThreadStore:
        (any RelayControllerThreadStoring)?
    private let updateContinuation:
        AsyncStream<[RelayPendingInteraction]>.Continuation
    private var records: [String: Record] = [:]
    private var eventTask: Task<Void, Never>?

    public init(
        rpc: any CodexSessionRPC,
        controllerThreadStore:
            (any RelayControllerThreadStoring)? = nil
    ) {
        self.rpc = rpc
        self.controllerThreadStore = controllerThreadStore
        let pair = AsyncStream<[RelayPendingInteraction]>.makeStream(
            bufferingPolicy: .bufferingNewest(1)
        )
        updates = pair.stream
        updateContinuation = pair.continuation
    }

    deinit {
        eventTask?.cancel()
        updateContinuation.finish()
    }

    public func start() async throws {
        guard eventTask == nil else { return }
        let events = rpc.events
        eventTask = Task { [weak self] in
            for await event in events {
                guard !Task.isCancelled else { return }
                switch event {
                case let .serverRequest(request):
                    _ = await self?.retain(request)
                case .lifecycle(.failed),
                     .lifecycle(.stopping),
                     .lifecycle(.stopped):
                    await self?.discardUnanswerableRequests()
                case .lifecycle, .notification, .protocolIssue:
                    break
                }
            }
        }
        try await rpc.start()
    }

    @discardableResult
    public func retain(
        _ request: CodexServerRequest
    ) async -> RelayPendingInteraction? {
        guard let params = request.params?.objectValue,
              let threadID = Self.threadID(in: params) else {
            return nil
        }
        let controllerThreadID = await controllerThreadStore?.loadThreadID()
        if threadID == controllerThreadID {
            return nil
        }
        guard let parsed = Self.parse(request, params: params) else {
            return nil
        }

        let interactionID = Self.interactionID(
            requestID: request.id,
            threadID: threadID,
            itemID: params["itemId"]?.stringValue
        )
        let interaction = RelayPendingInteraction(
            id: interactionID,
            threadID: threadID,
            turnID: params["turnId"]?.stringValue,
            kind: parsed.kind
        )
        records[interactionID] = Record(
            requestID: request.id,
            interaction: interaction,
            responseProtocol: parsed.responseProtocol
        )
        publish()
        return interaction
    }

    public func interactions() -> [RelayPendingInteraction] {
        records.values.map(\.interaction).sorted { $0.id < $1.id }
    }

    public func interaction(id: String) -> RelayPendingInteraction? {
        records[id]?.interaction
    }

    public func interaction(threadID: String) -> RelayPendingInteraction? {
        records.values
            .map(\.interaction)
            .filter { $0.threadID == threadID }
            .sorted { $0.id < $1.id }
            .first
    }

    public func submitAnswers(
        interactionID: String,
        answers: [String: [String]]
    ) async throws {
        guard let record = records[interactionID] else {
            throw RelayPendingInteractionBrokerError
                .unknownInteraction(interactionID)
        }
        guard case let .questions(questions) = record.interaction.kind,
              record.responseProtocol == .questions else {
            throw RelayPendingInteractionBrokerError.wrongInteractionKind
        }
        let expectedIDs = Set(questions.map(\.id))
        guard Set(answers.keys) == expectedIDs,
              answers.values.allSatisfy({ !$0.isEmpty }) else {
            throw RelayPendingInteractionBrokerError.incompleteAnswers
        }

        let encoded = answers.mapValues { values in
            JSONValue.object([
                "answers": .array(values.map(JSONValue.string)),
            ])
        }
        try await rpc.respond(
            to: record.requestID,
            result: .object(["answers": .object(encoded)])
        )
        records.removeValue(forKey: interactionID)
        publish()
    }

    public func submitDecision(
        interactionID: String,
        decision: RelayPendingApprovalDecision
    ) async throws {
        guard let record = records[interactionID] else {
            throw RelayPendingInteractionBrokerError
                .unknownInteraction(interactionID)
        }
        guard case let .approval(approval) = record.interaction.kind else {
            throw RelayPendingInteractionBrokerError.wrongInteractionKind
        }
        guard decision == .approve ? approval.canApprove : approval.canDecline
        else {
            throw RelayPendingInteractionBrokerError.unsupportedDecision
        }

        let result: JSONValue
        switch (record.responseProtocol, decision) {
        case (.modernApproval, .approve):
            result = .object(["decision": .string("accept")])
        case (.modernApproval, .decline):
            result = .object(["decision": .string("decline")])
        case (.legacyApproval, .approve):
            result = .object(["decision": .string("approved")])
        case (.legacyApproval, .decline):
            result = .object(["decision": .string("denied")])
        case (.permissions, .decline):
            result = .object([
                "permissions": .object([:]),
                "scope": .string("turn"),
            ])
        case (.elicitation, .decline):
            result = .object([
                "action": .string("decline"),
                "content": .null,
            ])
        default:
            throw RelayPendingInteractionBrokerError.unsupportedDecision
        }

        try await rpc.respond(to: record.requestID, result: result)
        records.removeValue(forKey: interactionID)
        publish()
    }

    private func publish() {
        updateContinuation.yield(interactions())
    }

    private func discardUnanswerableRequests() {
        guard !records.isEmpty else { return }
        records.removeAll()
        publish()
    }
}

private extension RelayPendingInteractionBroker {
    struct Record {
        let requestID: JSONRPCRequestID
        let interaction: RelayPendingInteraction
        let responseProtocol: ResponseProtocol
    }

    struct ParsedRequest {
        let kind: RelayPendingInteractionKind
        let responseProtocol: ResponseProtocol
    }

    enum ResponseProtocol: Equatable {
        case questions
        case modernApproval
        case legacyApproval
        case permissions
        case elicitation
    }

    static func parse(
        _ request: CodexServerRequest,
        params: [String: JSONValue]
    ) -> ParsedRequest? {
        switch request.method {
        case "item/tool/requestUserInput":
            let questions = params["questions"]?.arrayValue?.compactMap {
                value -> RelayPendingQuestion? in
                guard let object = value.objectValue,
                      let id = object["id"]?.stringValue,
                      let header = object["header"]?.stringValue,
                      let question = object["question"]?.stringValue else {
                    return nil
                }
                let options = object["options"]?.arrayValue?.compactMap {
                    option -> RelayPendingQuestionOption? in
                    guard let label = option["label"]?.stringValue,
                          let description = option["description"]?.stringValue
                    else {
                        return nil
                    }
                    return RelayPendingQuestionOption(
                        label: label,
                        description: description
                    )
                } ?? []
                return RelayPendingQuestion(
                    id: id,
                    header: header,
                    question: question,
                    options: options,
                    allowsOther: boolValue(object["isOther"]) ?? false,
                    isSecret: boolValue(object["isSecret"]) ?? false
                )
            } ?? []
            guard !questions.isEmpty else { return nil }
            return ParsedRequest(
                kind: .questions(questions),
                responseProtocol: .questions
            )

        case "item/commandExecution/requestApproval",
             "item/fileChange/requestApproval":
            let available = Set(
                params["availableDecisions"]?.arrayValue?
                    .compactMap(\.stringValue) ?? ["accept", "decline"]
            )
            return approval(
                params: params,
                protocol: .modernApproval,
                canApprove: available.contains("accept"),
                canDecline: available.contains("decline")
            )

        case "applyPatchApproval", "execCommandApproval":
            return approval(
                params: params,
                protocol: .legacyApproval,
                canApprove: true,
                canDecline: true
            )

        case "item/permissions/requestApproval":
            return approval(
                params: params,
                protocol: .permissions,
                canApprove: false,
                canDecline: true
            )

        case "mcpServer/elicitation/request":
            return ParsedRequest(
                kind: .approval(
                    RelayPendingApproval(
                        title: params["message"]?.stringValue
                            ?? "Codex needs a response",
                        detail: params["serverName"]?.stringValue,
                        canApprove: false,
                        canDecline: true
                    )
                ),
                responseProtocol: .elicitation
            )

        default:
            return nil
        }
    }

    static func approval(
        params: [String: JSONValue],
        protocol responseProtocol: ResponseProtocol,
        canApprove: Bool,
        canDecline: Bool
    ) -> ParsedRequest {
        let command = params["command"]?.stringValue
        let reason = params["reason"]?.stringValue
        let detail = [command, reason]
            .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .joined(separator: "\n")
        return ParsedRequest(
            kind: .approval(
                RelayPendingApproval(
                    title: command == nil
                        ? "Approve file or permission change?"
                        : "Approve command?",
                    detail: detail.isEmpty ? nil : detail,
                    canApprove: canApprove,
                    canDecline: canDecline
                )
            ),
            responseProtocol: responseProtocol
        )
    }

    static func interactionID(
        requestID: JSONRPCRequestID,
        threadID: String,
        itemID: String?
    ) -> String {
        let requestComponent = switch requestID {
        case let .integer(value): String(value)
        case let .string(value): value
        }
        return [threadID, itemID, requestComponent]
            .compactMap { $0 }
            .joined(separator: ":")
    }

    static func threadID(in params: [String: JSONValue]) -> String? {
        params["threadId"]?.stringValue
            ?? params["conversationId"]?.stringValue
    }

    static func boolValue(_ value: JSONValue?) -> Bool? {
        guard case let .bool(result) = value else { return nil }
        return result
    }
}
