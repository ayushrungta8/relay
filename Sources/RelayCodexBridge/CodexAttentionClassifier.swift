import Foundation
import RelayBrain
import RelayCore

public enum CodexAttentionClassifierError: Error, Sendable, Equatable {
    case malformedResponse
    case unexpectedToolCall
    case timedOut
}

public actor CodexAttentionClassifier: RelayAttentionAIClassifying {
    private static let configuration = RelayControllerConfiguration(
        developerInstructions: """
            You classify whether the final response from another Codex task is
            genuinely waiting for the user before useful work can continue.
            Return exactly one JSON object and no Markdown:
            {"needs_reply":true|false,"confidence":"high|low","reason":"short reason"}

            Mark needs_reply true when the response requests approval,
            confirmation, a choice, missing information, an attachment, a
            manual check, or another concrete reply. Mark it false for a
            completed result, optional offer, rhetorical question, or generic
            invitation such as "let me know if you have questions". Use high
            confidence only when the message itself clearly supports the
            decision.
            """,
        dynamicTools: [],
        model: "gpt-5.6-terra",
        reasoningEffort: "low"
    )

    private let session: any RelayControllerSession
    private let timeout: Duration
    private var controller: RelayControllerThread?
    private var isClassifying = false
    private var waiters: [CheckedContinuation<Void, Never>] = []

    public init(
        session: any RelayControllerSession,
        timeout: Duration = .seconds(20)
    ) {
        self.session = session
        self.timeout = timeout
    }

    public func classify(
        _ text: String
    ) async throws -> RelayAIAttentionClassification {
        await acquire()
        defer { release() }

        let controller = try await controllerThread()
        let input = Self.boundedInput(text)
        let prompt = """
            Classify this final Codex response:

            <response>
            \(input)
            </response>
            """
        let events = try await session.submitUserText(prompt, to: controller)
        let answer: String
        do {
            answer = try await withThrowingTaskGroup(of: String.self) { group in
                group.addTask {
                    try await Self.collectAnswer(from: events)
                }
                group.addTask { [timeout] in
                    try await Task.sleep(for: timeout)
                    throw CodexAttentionClassifierError.timedOut
                }
                guard let first = try await group.next() else {
                    throw CodexAttentionClassifierError.malformedResponse
                }
                group.cancelAll()
                return first
            }
        } catch {
            await session.cancelActiveTurn()
            throw error
        }
        return try Self.decode(answer)
    }

    private func controllerThread() async throws -> RelayControllerThread {
        if let controller { return controller }
        let controller = try await session.ensureControllerThread(
            configuration: Self.configuration
        )
        self.controller = controller
        return controller
    }

    private func acquire() async {
        if !isClassifying {
            isClassifying = true
            return
        }
        await withCheckedContinuation { continuation in
            waiters.append(continuation)
        }
    }

    private func release() {
        if waiters.isEmpty {
            isClassifying = false
        } else {
            waiters.removeFirst().resume()
        }
    }

    private static func collectAnswer(
        from events: AsyncThrowingStream<RelayControllerEvent, any Error>
    ) async throws -> String {
        var finalText: String?
        for try await event in events {
            switch event {
            case .dynamicToolCall:
                throw CodexAttentionClassifierError.unexpectedToolCall
            case .textDelta:
                break
            case let .finalText(text):
                finalText = text
            }
        }
        guard let finalText else {
            throw CodexAttentionClassifierError.malformedResponse
        }
        return finalText
    }

    private static func boundedInput(_ text: String) -> String {
        let limit = 12_000
        guard text.count > limit else { return text }
        return String(text.prefix(2_000))
            + "\n[…middle omitted…]\n"
            + String(text.suffix(10_000))
    }

    static func decode(
        _ answer: String
    ) throws -> RelayAIAttentionClassification {
        let trimmed = answer.trimmingCharacters(in: .whitespacesAndNewlines)
        let json: String
        if trimmed.hasPrefix("```") {
            let lines = trimmed.split(
                separator: "\n",
                omittingEmptySubsequences: false
            )
            guard lines.count >= 3 else {
                throw CodexAttentionClassifierError.malformedResponse
            }
            json = lines.dropFirst().dropLast().joined(separator: "\n")
        } else {
            json = trimmed
        }
        guard let data = json.data(using: .utf8),
              let response = try? JSONDecoder().decode(
                  ClassifierResponse.self,
                  from: data
              ) else {
            throw CodexAttentionClassifierError.malformedResponse
        }
        return RelayAIAttentionClassification(
            needsReply: response.needsReply
                && response.confidence.lowercased() == "high",
            reason: response.reason
        )
    }
}

private struct ClassifierResponse: Decodable {
    let needsReply: Bool
    let confidence: String
    let reason: String

    private enum CodingKeys: String, CodingKey {
        case needsReply = "needs_reply"
        case confidence
        case reason
    }
}
