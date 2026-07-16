import Foundation

final class CodexServerEventBroadcaster: @unchecked Sendable {
    private let lock = NSLock()
    private var continuations: [
        UUID: AsyncStream<CodexServerEvent>.Continuation
    ] = [:]
    private var isFinished = false

    func stream() -> AsyncStream<CodexServerEvent> {
        let id = UUID()
        return AsyncStream(bufferingPolicy: .unbounded) { continuation in
            let shouldFinish = lock.withLock {
                guard !isFinished else { return true }
                continuations[id] = continuation
                return false
            }
            if shouldFinish {
                continuation.finish()
                return
            }
            continuation.onTermination = { [weak self] _ in
                self?.removeContinuation(id: id)
            }
        }
    }

    func yield(_ event: CodexServerEvent) {
        let current = lock.withLock {
            Array(continuations.values)
        }
        for continuation in current {
            continuation.yield(event)
        }
    }

    func finish() {
        let current = lock.withLock {
            isFinished = true
            defer { continuations.removeAll() }
            return Array(continuations.values)
        }
        for continuation in current {
            continuation.finish()
        }
    }

    private func removeContinuation(id: UUID) {
        _ = lock.withLock {
            continuations.removeValue(forKey: id)
        }
    }
}
