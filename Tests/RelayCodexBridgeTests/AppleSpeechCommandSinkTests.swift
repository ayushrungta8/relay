import Foundation
import RelayCodexBridge
import RelayVoice
import Testing

struct AppleSpeechCommandSinkTests {
    @Test
    func releaseTranscribesAudioAndRoutesTextThroughTheController()
        async throws
    {
        let transcriber = SpeechTranscriberStub(
            transcript: "What tasks are running?"
        )
        let controller = SpeechCommandHandlerStub(
            result: .success("Two worker tasks are active.")
        )
        let recorder = SpeechVoiceEventRecorder()
        let sink = AppleSpeechCommandSink(
            transcriber: transcriber,
            commandHandler: controller,
            onEvent: { event in
                await recorder.record(event)
            }
        )
        let chunk = RelayAudioChunk(
            pcmData: Data([1, 2, 3, 4]),
            sampleRate: 24_000,
            numChannels: 1,
            samplesPerChannel: 2
        )

        try await sink.start()
        try await sink.append(chunk)
        try await sink.finishAndSend()

        #expect(
            await transcriber.recordedEvents()
                == [.start, .append(chunk), .finish]
        )
        #expect(
            await controller.prompts()
                == ["What tasks are running?"]
        )
        #expect(
            await recorder.events()
                == [
                    .transcript("What tasks are running?"),
                    .answer("Two worker tasks are active."),
                ]
        )
    }

    @Test
    func cancelDiscardsSpeechWithoutCallingTheController() async throws {
        let transcriber = SpeechTranscriberStub(
            transcript: "Discard this"
        )
        let controller = SpeechCommandHandlerStub(
            result: .success("Unexpected")
        )
        let sink = AppleSpeechCommandSink(
            transcriber: transcriber,
            commandHandler: controller
        )

        try await sink.start()
        await sink.cancel()

        #expect(
            await transcriber.recordedEvents()
                == [.start, .cancel]
        )
        #expect(await controller.prompts().isEmpty)
    }

    @Test
    func controllerFailureIsPublishedAndCanBeRetried() async throws {
        let transcriber = SpeechTranscriberStub(
            transcripts: ["First command", "Second command"]
        )
        let controller = SpeechCommandHandlerStub(
            results: [
                .failure(SpeechCommandTestError.controllerFailed),
                .success("Second command worked."),
            ]
        )
        let recorder = SpeechVoiceEventRecorder()
        let sink = AppleSpeechCommandSink(
            transcriber: transcriber,
            commandHandler: controller,
            onEvent: { event in
                await recorder.record(event)
            }
        )

        try await sink.start()
        await #expect(throws: SpeechCommandTestError.self) {
            try await sink.finishAndSend()
        }

        try await sink.start()
        try await sink.finishAndSend()

        #expect(
            await controller.prompts()
                == ["First command", "Second command"]
        )
        #expect(
            await recorder.events()
                == [
                    .transcript("First command"),
                    .failed("The controller failed."),
                    .transcript("Second command"),
                    .answer("Second command worked."),
                ]
        )
    }

    @Test
    func cancelDuringTranscriberStartupCannotResurrectTheSink()
        async throws
    {
        let transcriber = BlockingStartSpeechTranscriber()
        let controller = SpeechCommandHandlerStub(
            result: .success("Unexpected")
        )
        let sink = AppleSpeechCommandSink(
            transcriber: transcriber,
            commandHandler: controller
        )

        let startTask = Task {
            try await sink.start()
        }
        await transcriber.waitUntilStartEntered()
        await sink.cancel()
        await transcriber.unblockStart()

        await #expect(throws: CancellationError.self) {
            try await startTask.value
        }

        try await sink.start()
        await sink.cancel()
    }
}

private actor SpeechTranscriberStub: RelaySpeechTranscribing {
    private var transcripts: [String]
    private var events: [SpeechTranscriberEvent] = []

    init(transcript: String) {
        transcripts = [transcript]
    }

    init(transcripts: [String]) {
        self.transcripts = transcripts
    }

    func start() {
        events.append(.start)
    }

    func append(_ chunk: RelayAudioChunk) {
        events.append(.append(chunk))
    }

    func finish() throws -> String {
        events.append(.finish)
        guard !transcripts.isEmpty else {
            throw SpeechCommandTestError.noTranscript
        }
        return transcripts.removeFirst()
    }

    func cancel() {
        events.append(.cancel)
    }

    func recordedEvents() -> [SpeechTranscriberEvent] {
        events
    }
}

private enum SpeechTranscriberEvent: Equatable {
    case start
    case append(RelayAudioChunk)
    case finish
    case cancel
}

private actor BlockingStartSpeechTranscriber:
    RelaySpeechTranscribing
{
    private var shouldBlockNextStart = true
    private var startContinuation:
        CheckedContinuation<Void, Never>?
    private var enteredWaiters:
        [CheckedContinuation<Void, Never>] = []
    private var didEnterStart = false

    func start() async {
        guard shouldBlockNextStart else { return }
        shouldBlockNextStart = false
        didEnterStart = true
        let waiters = enteredWaiters
        enteredWaiters.removeAll()
        for waiter in waiters {
            waiter.resume()
        }
        await withCheckedContinuation { continuation in
            startContinuation = continuation
        }
    }

    func append(_ chunk: RelayAudioChunk) {}

    func finish() -> String {
        "Unexpected"
    }

    func cancel() {}

    func waitUntilStartEntered() async {
        if didEnterStart { return }
        await withCheckedContinuation { continuation in
            enteredWaiters.append(continuation)
        }
    }

    func unblockStart() {
        startContinuation?.resume()
        startContinuation = nil
    }
}

private actor SpeechCommandHandlerStub: RelayCommandHandling {
    private var results: [Result<String, any Error>]
    private var recordedPrompts: [String] = []

    init(result: Result<String, any Error>) {
        results = [result]
    }

    init(results: [Result<String, any Error>]) {
        self.results = results
    }

    func submit(_ text: String) throws -> String {
        recordedPrompts.append(text)
        guard !results.isEmpty else {
            throw SpeechCommandTestError.controllerFailed
        }
        return try results.removeFirst().get()
    }

    func prompts() -> [String] {
        recordedPrompts
    }
}

private actor SpeechVoiceEventRecorder {
    private var recorded: [RelayVoiceControllerEvent] = []

    func record(_ event: RelayVoiceControllerEvent) {
        recorded.append(event)
    }

    func events() -> [RelayVoiceControllerEvent] {
        recorded
    }
}

private enum SpeechCommandTestError: Error, LocalizedError {
    case controllerFailed
    case noTranscript

    var errorDescription: String? {
        switch self {
        case .controllerFailed:
            "The controller failed."
        case .noTranscript:
            "No transcript."
        }
    }
}
