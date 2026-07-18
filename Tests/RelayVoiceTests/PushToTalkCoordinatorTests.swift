import AVFoundation
import Foundation
import Testing
@testable import RelayVoice

struct RelayAudioChunkTests {
    @Test
    func base64EncodesPCMDataUsingTheAppServerAudioShape() {
        let chunk = RelayAudioChunk(
            pcmData: Data([0x00, 0x01, 0xFE]),
            sampleRate: 24_000,
            numChannels: 1,
            samplesPerChannel: 3
        )

        #expect(chunk.data == "AAH+")
        #expect(chunk.sampleRate == 24_000)
        #expect(chunk.numChannels == 1)
        #expect(chunk.samplesPerChannel == 3)
    }
}

struct RelayGlobalShortcutTests {
    @Test
    func prototypeDefaultIsOptionSpace() {
        #expect(RelayGlobalShortcut.default.keyCode == 49)
        #expect(RelayGlobalShortcut.default.modifiers == [.option])
    }
}

struct AudioTapCallbackTests {
    @Test
    func forwardsBuffersThroughANonisolatedCallback() throws {
        let processor = RecordingAudioTapProcessor()
        let callback =
            AVAudioEngineMicrophoneCapture.makeAudioTapBlock(
                processor: processor
            )
        let format = try #require(
            AVAudioFormat(
                commonFormat: .pcmFormatFloat32,
                sampleRate: 48_000,
                channels: 1,
                interleaved: false
            )
        )
        let buffer = try #require(
            AVAudioPCMBuffer(
                pcmFormat: format,
                frameCapacity: 16
            )
        )

        callback(buffer, AVAudioTime())

        #expect(processor.receivedBufferCount == 1)
    }
}

@MainActor
struct AVAudioEngineMicrophoneCaptureTests {
    @Test
    func initializationDoesNotInspectPermissionOrCreateAnAudioEngine() {
        var permissionInspectionCount = 0
        var engineCreationCount = 0

        _ = AVAudioEngineMicrophoneCapture(
            authorizationStatusProvider: {
                permissionInspectionCount += 1
                return .authorized
            },
            engineFactory: {
                engineCreationCount += 1
                return AVAudioEngine()
            }
        )

        #expect(permissionInspectionCount == 0)
        #expect(engineCreationCount == 0)
    }

    @Test
    func deniedPermissionFailsBeforeCreatingAnAudioEngine() {
        var engineCreationCount = 0
        let capture = AVAudioEngineMicrophoneCapture(
            authorizationStatusProvider: { .denied },
            engineFactory: {
                engineCreationCount += 1
                return AVAudioEngine()
            }
        )

        do {
            _ = try capture.start()
            Issue.record("Expected denied microphone permission to fail.")
        } catch let error as RelayMicrophoneCaptureError {
            #expect(error == .permissionDenied)
        } catch {
            Issue.record("Unexpected error: \(error)")
        }

        #expect(engineCreationCount == 0)
    }

    @Test
    func restrictedPermissionFailsBeforeCreatingAnAudioEngine() {
        var engineCreationCount = 0
        let capture = AVAudioEngineMicrophoneCapture(
            authorizationStatusProvider: { .restricted },
            engineFactory: {
                engineCreationCount += 1
                return AVAudioEngine()
            }
        )

        do {
            _ = try capture.start()
            Issue.record("Expected restricted microphone permission to fail.")
        } catch let error as RelayMicrophoneCaptureError {
            #expect(error == .permissionRestricted)
        } catch {
            Issue.record("Unexpected error: \(error)")
        }

        #expect(engineCreationCount == 0)
    }
}

private final class RecordingAudioTapProcessor:
    RelayAudioTapProcessing,
    @unchecked Sendable
{
    private let lock = NSLock()
    private var count = 0

    var receivedBufferCount: Int {
        lock.withLock { count }
    }

    func process(_ buffer: AVAudioPCMBuffer) {
        lock.withLock {
            count += 1
        }
    }
}

struct PushToTalkStateMachineTests {
    @Test
    func reducesACompletePressAndReleaseCycle() {
        var machine = PushToTalkStateMachine()

        #expect(machine.send(.pressed) == .startListening)
        #expect(machine.state == .listening)
        #expect(machine.send(.pressed) == nil)
        #expect(machine.send(.released) == .finishAndSend)
        #expect(machine.state == .finishing)
        #expect(machine.send(.released) == nil)
        #expect(machine.send(.completed) == nil)
        #expect(machine.state == .idle)
    }

    @Test
    func cancelMovesAnActiveTurnThroughFinishing() {
        var machine = PushToTalkStateMachine()

        _ = machine.send(.pressed)

        #expect(machine.send(.cancelRequested) == .cancel)
        #expect(machine.state == .finishing)
        #expect(machine.send(.completed) == nil)
        #expect(machine.state == .idle)
    }

    @Test
    func failureCanBeRetriedWithANewPress() {
        var machine = PushToTalkStateMachine()

        _ = machine.send(.pressed)
        let failure = RelayPushToTalkFailure(message: "offline")
        #expect(machine.send(.failed(failure)) == nil)
        #expect(machine.state == .failed(failure))
        #expect(machine.send(.pressed) == .startListening)
        #expect(machine.state == .listening)
    }
}

@MainActor
struct PushToTalkCoordinatorTests {
    @Test
    func ignoresDuplicatePresses() async {
        let capture = FakeMicrophoneCapture()
        let sink = RecordingAudioSink()
        let coordinator = PushToTalkCoordinator(
            microphone: capture,
            sink: sink
        )

        coordinator.press()
        coordinator.press()
        await coordinator.release()

        #expect(capture.startCount == 1)
        #expect(await sink.count(of: .start) == 1)
        #expect(await sink.count(of: .finish) == 1)
    }

    @Test
    func streamsChunksInOrderAndFinishesExactlyOnceOnRelease() async {
        let capture = FakeMicrophoneCapture()
        let sink = RecordingAudioSink()
        let coordinator = PushToTalkCoordinator(
            microphone: capture,
            sink: sink
        )
        let first = RelayAudioChunk.fixture(byte: 1)
        let second = RelayAudioChunk.fixture(byte: 2)

        coordinator.press()
        capture.emit(first)
        capture.emit(second)

        async let firstRelease: Void = coordinator.release()
        await Task.yield()
        async let duplicateRelease: Void = coordinator.release()
        _ = await (firstRelease, duplicateRelease)

        #expect(
            await sink.recordedEvents()
                == [.start, .append(first), .append(second), .finish]
        )
        #expect(capture.stopCount == 1)
        #expect(coordinator.state == .idle)
    }

    @Test
    func cancelDiscardsWithoutFinishing() async {
        let capture = FakeMicrophoneCapture()
        let sink = RecordingAudioSink()
        let coordinator = PushToTalkCoordinator(
            microphone: capture,
            sink: sink
        )

        coordinator.press()
        capture.emit(.fixture(byte: 7))
        #expect(
            await eventually {
                await sink.count(of: .append(.fixture(byte: 7))) == 1
            }
        )

        await coordinator.cancel()

        #expect(await sink.count(of: .cancel) == 1)
        #expect(await sink.count(of: .finish) == 0)
        #expect(capture.stopCount == 1)
        #expect(coordinator.state == .idle)
    }

    @Test
    func cancelInterruptsAPendingSinkStart() async {
        let capture = FakeMicrophoneCapture()
        let sink = BlockingStartAudioSink()
        let coordinator = PushToTalkCoordinator(
            microphone: capture,
            sink: sink
        )

        coordinator.press()
        #expect(
            await eventually {
                await sink.didEnterStart()
            }
        )

        let cancellation = Task { @MainActor in
            await coordinator.cancel()
        }
        try? await Task.sleep(for: .milliseconds(20))
        let cancelCountBeforeManualUnblock =
            await sink.cancelCount()
        await sink.unblockStart()
        await cancellation.value

        #expect(cancelCountBeforeManualUnblock == 1)
        #expect(await sink.finishCount() == 0)
        #expect(coordinator.state == .idle)
    }

    @Test
    func startFailureStopsCaptureCancelsTheSinkAndPublishesFailure() async {
        let capture = FakeMicrophoneCapture()
        let sink = RecordingAudioSink(startError: TestFailure.expected)
        let coordinator = PushToTalkCoordinator(
            microphone: capture,
            sink: sink
        )

        coordinator.press()

        #expect(
            await eventually {
                if case .failed = coordinator.state {
                    return true
                }
                return false
            }
        )
        #expect(capture.stopCount == 1)
        #expect(await sink.count(of: .cancel) == 1)
        #expect(await sink.count(of: .finish) == 0)
    }

    @Test
    func startFailurePreservesItsReadinessBlocker() async {
        let coordinator = PushToTalkCoordinator(
            microphone: FakeMicrophoneCapture(),
            sink: RecordingAudioSink(
                startError: ReadinessFixtureError.dictationDisabled
            )
        )

        coordinator.press()

        #expect(
            await eventually {
                guard case let .failed(failure) = coordinator.state else {
                    return false
                }
                return failure.readinessState == .dictationDisabled
                    && !failure.message.isEmpty
            }
        )
    }

    @Test
    func publishesStateTransitionsForTheAppShell() async {
        let capture = FakeMicrophoneCapture()
        let sink = RecordingAudioSink()
        var states: [PushToTalkState] = []
        let coordinator = PushToTalkCoordinator(
            microphone: capture,
            sink: sink,
            onStateChange: { states.append($0) }
        )

        coordinator.press()
        await coordinator.release()

        #expect(states == [.listening, .finishing, .idle])
    }
}

@MainActor
private final class FakeMicrophoneCapture: RelayMicrophoneCapturing {
    private var continuation:
        AsyncStream<RelayAudioChunk>.Continuation?

    private(set) var startCount = 0
    private(set) var stopCount = 0

    func start() throws -> AsyncStream<RelayAudioChunk> {
        startCount += 1
        let pair = AsyncStream<RelayAudioChunk>.makeStream(
            bufferingPolicy: .unbounded
        )
        continuation = pair.continuation
        return pair.stream
    }

    func stop() {
        stopCount += 1
        continuation?.finish()
        continuation = nil
    }

    func emit(_ chunk: RelayAudioChunk) {
        continuation?.yield(chunk)
    }
}

private actor RecordingAudioSink: RelayRealtimeAudioSink {
    enum Event: Equatable, Sendable {
        case start
        case append(RelayAudioChunk)
        case finish
        case cancel
    }

    private var events: [Event] = []
    private let startError: (any Error)?

    init(startError: (any Error)? = nil) {
        self.startError = startError
    }

    func start() async throws {
        events.append(.start)
        if let startError {
            throw startError
        }
    }

    func append(_ chunk: RelayAudioChunk) async throws {
        events.append(.append(chunk))
    }

    func finishAndSend() async throws {
        events.append(.finish)
    }

    func cancel() async {
        events.append(.cancel)
    }

    func recordedEvents() -> [Event] {
        events
    }

    func count(of event: Event) -> Int {
        events.count(where: { $0 == event })
    }
}

private actor BlockingStartAudioSink: RelayRealtimeAudioSink {
    private var startContinuation:
        CheckedContinuation<Void, any Error>?
    private var enteredStart = false
    private var cancellations = 0
    private var finishes = 0

    func start() async throws {
        enteredStart = true
        try await withCheckedThrowingContinuation {
            startContinuation = $0
        }
    }

    func append(_ chunk: RelayAudioChunk) async throws {}

    func finishAndSend() async throws {
        finishes += 1
    }

    func cancel() async {
        cancellations += 1
        startContinuation?.resume(throwing: CancellationError())
        startContinuation = nil
    }

    func didEnterStart() -> Bool {
        enteredStart
    }

    func cancelCount() -> Int {
        cancellations
    }

    func finishCount() -> Int {
        finishes
    }

    func unblockStart() {
        startContinuation?.resume()
        startContinuation = nil
    }
}

private enum TestFailure: Error {
    case expected
}

private enum ReadinessFixtureError:
    Error,
    RelayVoiceReadinessFailure
{
    case dictationDisabled

    var voiceReadinessState: RelayVoiceReadinessState? {
        .dictationDisabled
    }
}

private extension RelayAudioChunk {
    static func fixture(byte: UInt8) -> RelayAudioChunk {
        RelayAudioChunk(
            pcmData: Data([byte]),
            sampleRate: 24_000,
            numChannels: 1,
            samplesPerChannel: 1
        )
    }
}

private func eventually(
    _ predicate: @escaping @MainActor () async -> Bool
) async -> Bool {
    for _ in 0..<100 {
        if await predicate() {
            return true
        }
        try? await Task.sleep(for: .milliseconds(5))
    }
    return false
}
