import Foundation
import RelayBrain

public protocol RelayCommandHandling: Sendable {
    func submit(_ text: String) async throws -> String
    func submit(
        _ text: String,
        onAnswerUpdate: @escaping @Sendable (String) async -> Void
    ) async throws -> String
}

public extension RelayCommandHandling {
    func submit(
        _ text: String,
        onAnswerUpdate: @escaping @Sendable (String) async -> Void
    ) async throws -> String {
        let answer = try await submit(text)
        await onAnswerUpdate(answer)
        return answer
    }
}

public actor RelayControllerRuntime: RelayCommandHandling {
    private let session: any RelayControllerSession
    private let router: RelayToolCallRouter
    private let configuration: RelayControllerConfiguration
    private var controller: RelayControllerThread?

    public init(
        session: any RelayControllerSession,
        router: RelayToolCallRouter,
        configuration: RelayControllerConfiguration = .default
    ) {
        self.session = session
        self.router = router
        self.configuration = configuration
    }

    public func submit(_ text: String) async throws -> String {
        try await submit(text, onAnswerUpdate: { _ in })
    }

    public func submit(
        _ text: String,
        onAnswerUpdate: @escaping @Sendable (String) async -> Void
    ) async throws -> String {
        let controller = try await controllerThread()
        let events = try await session.submitUserText(
            text,
            to: controller
        )
        return try await RelayControllerEventProcessor.answer(
            from: events,
            session: session,
            router: router,
            onAnswerUpdate: onAnswerUpdate
        )
    }

    private func controllerThread() async throws -> RelayControllerThread {
        if let controller {
            return controller
        }

        let controller = try await session.ensureControllerThread(
            configuration: configuration
        )
        self.controller = controller
        return controller
    }
}
