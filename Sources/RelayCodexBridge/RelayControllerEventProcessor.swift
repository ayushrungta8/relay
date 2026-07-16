import Foundation
import RelayBrain

public enum RelayControllerEventProcessor {
    public static func answer(
        from events:
            AsyncThrowingStream<RelayControllerEvent, any Error>,
        session: any RelayControllerSession,
        router: RelayToolCallRouter
    ) async throws -> String {
        var finalText: String?

        for try await event in events {
            switch event {
            case let .dynamicToolCall(call):
                let result = await router.route(
                    toolName: call.toolName,
                    argumentsJSON: call.argumentsJSON
                )
                try await session.completeToolCall(call, with: result)
            case let .finalText(text):
                finalText = text
            }
        }

        guard let finalText else {
            throw CodexControllerSessionError.noControllerAnswer
        }
        return finalText
    }
}
