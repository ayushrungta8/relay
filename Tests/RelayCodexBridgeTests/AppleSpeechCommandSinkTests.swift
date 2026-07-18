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
        let synthesizer = SpeechSynthesizerSpy()
        let sink = AppleSpeechCommandSink(
            transcriber: transcriber,
            commandHandler: controller,
            synthesizer: synthesizer,
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
                    .answerUpdate("Two worker tasks are active."),
                    .answer("Two worker tasks are active."),
                ]
        )
        // Voice in → voice out: the press barges in (stop) and the final
        // answer is spoken back as a short summary.
        #expect(
            await synthesizer.calls()
                == [.stop, .speak("Two worker tasks are active.")]
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
        let synthesizer = SpeechSynthesizerSpy()
        let sink = AppleSpeechCommandSink(
            transcriber: transcriber,
            commandHandler: controller,
            synthesizer: synthesizer
        )

        try await sink.start()
        await sink.cancel()

        #expect(
            await transcriber.recordedEvents()
                == [.start, .cancel]
        )
        #expect(await controller.prompts().isEmpty)
        // Nothing is spoken when the turn is cancelled; both the press
        // and the cancel barge in on any prior speech.
        #expect(await synthesizer.spokenTexts().isEmpty)
        #expect(await synthesizer.calls() == [.stop, .stop])
    }

    @Test
    func disabledSpokenResponsesDoNotSpeakTheCompletedAnswer() async throws {
        let transcriber = SpeechTranscriberStub(transcript: "Status")
        let controller = SpeechCommandHandlerStub(
            result: .success("Everything is complete.")
        )
        let synthesizer = SpeechSynthesizerSpy()
        let sink = AppleSpeechCommandSink(
            transcriber: transcriber,
            commandHandler: controller,
            synthesizer: synthesizer,
            shouldSpeakResponses: { false }
        )

        try await sink.start()
        try await sink.finishAndSend()

        #expect(await synthesizer.spokenTexts().isEmpty)
        #expect(await synthesizer.calls() == [.stop])
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
        let synthesizer = SpeechSynthesizerSpy()
        let sink = AppleSpeechCommandSink(
            transcriber: transcriber,
            commandHandler: controller,
            synthesizer: synthesizer,
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
        // Only the successful answer is spoken; the failed turn stays
        // silent.
        #expect(
            await synthesizer.spokenTexts()
                == ["Second command worked."]
        )
        #expect(
            await recorder.events()
                == [
                    .transcript("First command"),
                    .failed("The controller failed."),
                    .transcript("Second command"),
                    .answerUpdate("Second command worked."),
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
            commandHandler: controller,
            synthesizer: SpeechSynthesizerSpy()
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

private actor SpeechSynthesizerSpy: RelaySpeechSynthesizing {
    private var recorded: [SpeechSynthesizerCall] = []

    func speak(_ text: String) {
        recorded.append(.speak(text))
    }

    func stop() {
        recorded.append(.stop)
    }

    func calls() -> [SpeechSynthesizerCall] {
        recorded
    }

    func spokenTexts() -> [String] {
        recorded.compactMap { call in
            if case let .speak(text) = call { text } else { nil }
        }
    }
}

private enum SpeechSynthesizerCall: Equatable {
    case speak(String)
    case stop
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
