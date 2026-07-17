import Foundation
import RelayBrain

public enum RelayControllerEventProcessor {
    public static func answer(
        from events:
            AsyncThrowingStream<RelayControllerEvent, any Error>,
        session: any RelayControllerSession,
        router: RelayToolCallRouter,
        onAnswerUpdate: @escaping @Sendable (String) async -> Void = { _ in }
    ) async throws -> String {
        var finalText: String?
        var accumulatedText = ""

        for try await event in events {
            switch event {
            case let .dynamicToolCall(call):
                let result = await router.route(
                    toolName: call.toolName,
                    argumentsJSON: call.argumentsJSON
                )
                try await session.completeToolCall(call, with: result)
            case let .textDelta(delta):
                accumulatedText += delta
                await onAnswerUpdate(accumulatedText)
            case let .finalText(text):
                finalText = text
                if text != accumulatedText {
                    await onAnswerUpdate(text)
                }
            }
        }

        guard let finalText else {
            throw CodexControllerSessionError.noControllerAnswer
        }
        return finalText
    }
}
