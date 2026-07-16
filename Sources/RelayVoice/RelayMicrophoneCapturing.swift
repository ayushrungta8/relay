@MainActor
public protocol RelayMicrophoneCapturing: AnyObject {
    func start() throws -> AsyncStream<RelayAudioChunk>
    func stop()
}
