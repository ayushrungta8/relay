import Foundation

public protocol CodexAppServerTransport: Sendable {
    func start() async throws -> AsyncThrowingStream<Data, any Error>
    func send(_ message: Data) async throws
    func stop() async
}
