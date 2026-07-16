public protocol RelayRealtimeAudioSink: Sendable {
    func start() async throws
    func append(_ chunk: RelayAudioChunk) async throws
    func finishAndSend() async throws
    func cancel() async
}
