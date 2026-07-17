import Foundation

@MainActor
final class RelayPanelPresentationCoordinator {
    typealias Sleep = @Sendable (Duration) async throws -> Void

    private let sleep: Sleep
    private let presentPeek: () -> Void
    private let dismissPeek: () -> Void
    private var lastTrigger: RelayAutomaticPeekTrigger?
    private var dismissalTask: Task<Void, Never>?

    init(
        sleep: @escaping Sleep = { try await Task.sleep(for: $0) },
        presentPeek: @escaping () -> Void,
        dismissPeek: @escaping () -> Void
    ) {
        self.sleep = sleep
        self.presentPeek = presentPeek
        self.dismissPeek = dismissPeek
    }

    func observe(_ trigger: RelayAutomaticPeekTrigger?) {
        guard let trigger, trigger != lastTrigger else { return }
        lastTrigger = trigger
        presentPeek()
        dismissalTask?.cancel()
        dismissalTask = Task { [weak self, sleep] in
            do {
                try await sleep(.seconds(4))
            } catch {
                return
            }
            guard let self, !Task.isCancelled else { return }
            dismissPeek()
        }
    }

    func cancelAutomaticDismissal() {
        dismissalTask?.cancel()
        dismissalTask = nil
    }

    deinit { dismissalTask?.cancel() }
}
