import Foundation
import RelayBrain

public protocol RelayCommandHandling: Sendable {
    func submit(_ text: String) async throws -> String
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
        let controller = try await controllerThread()
        let events = try await session.submitUserText(
            text,
            to: controller
        )
        return try await RelayControllerEventProcessor.answer(
            from: events,
            session: session,
            router: router
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
