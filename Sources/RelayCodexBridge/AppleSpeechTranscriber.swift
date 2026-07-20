@preconcurrency import AVFoundation
@preconcurrency import Speech
import Foundation
import RelayVoice

public protocol RelaySpeechTranscribing: Sendable {
    func start() async throws
    func append(_ chunk: RelayAudioChunk) async throws
    func finish() async throws -> String
    func cancel() async
}

public enum AppleSpeechTranscriberError:
    Error,
    Sendable,
    Equatable
{
    case alreadyRunning
    case notRunning
    case permissionDenied
    case permissionRestricted
    case recognizerUnavailable(String)
    case invalidAudio
    case noSpeech
    case timedOut
    case dictationDisabled
    case networkUnavailable
}

extension AppleSpeechTranscriberError: LocalizedError {
    public var errorDescription: String? {
        switch self {
        case .alreadyRunning:
            "Apple Speech recognition is already running."
        case .notRunning:
            "Apple Speech recognition is not running."
        case .permissionDenied:
            "Speech Recognition access is denied. Allow Relay in System Settings → Privacy & Security → Speech Recognition."
        case .permissionRestricted:
            "Speech Recognition is restricted on this Mac."
        case let .recognizerUnavailable(locale):
            "Apple Speech recognition is unavailable for locale \(locale)."
        case .invalidAudio:
            "Relay captured invalid microphone audio."
        case .noSpeech:
            "Relay did not hear a spoken command."
        case .timedOut:
            "Apple Speech did not finish transcribing in time."
        case .dictationDisabled:
            "Siri and Dictation are disabled. Enable Dictation in System Settings → Keyboard."
        case .networkUnavailable:
            "Speech Recognition needs an internet connection for this language."
        }
    }
}

extension AppleSpeechTranscriberError: RelayVoiceReadinessFailure {
    public var voiceReadinessState: RelayVoiceReadinessState? {
        switch self {
        case .permissionDenied:
            .speechRecognitionDenied
        case .permissionRestricted:
            .speechRecognitionRestricted
        case let .recognizerUnavailable(locale):
            .recognizerUnavailable(locale)
        case .dictationDisabled:
            .dictationDisabled
        case .networkUnavailable:
            .networkUnavailable
        case .alreadyRunning,
             .notRunning,
             .invalidAudio,
             .noSpeech,
             .timedOut:
            nil
        }
    }

    public static func classify(
        _ error: any Error
    ) -> AppleSpeechTranscriberError? {
        let cocoaError = error as NSError
        if cocoaError.localizedDescription
            .localizedCaseInsensitiveContains(
                "Siri and Dictation are disabled"
            ) {
            return .dictationDisabled
        }

        if let urlError = error as? URLError,
           [
               URLError.Code.notConnectedToInternet,
               .networkConnectionLost,
               .cannotConnectToHost,
               .timedOut,
           ].contains(urlError.code) {
            return .networkUnavailable
        }
        return nil
    }
}

public actor AppleSpeechTranscriber: RelaySpeechTranscribing {
    private let localeIdentifier: String
    private let transcriptionTimeout: Duration

    private var recognizer: SFSpeechRecognizer?
    private var recognitionRequest:
        SFSpeechAudioBufferRecognitionRequest?
    private var recognitionTask: SFSpeechRecognitionTask?
    private var resultStream:
        AsyncThrowingStream<RecognitionResult, any Error>?
    private var resultContinuation:
        AsyncThrowingStream<
            RecognitionResult,
            any Error
        >.Continuation?

    public init(
        localeIdentifier: String = RelaySpeechLocale.currentIdentifier,
        transcriptionTimeout: Duration = .seconds(5)
    ) {
        self.localeIdentifier = localeIdentifier
        self.transcriptionTimeout = transcriptionTimeout
    }

    public func start() async throws {
        guard recognitionTask == nil,
              recognitionRequest == nil else {
            throw AppleSpeechTranscriberError.alreadyRunning
        }

        try await ensureAuthorization()

        let locale = Locale(identifier: localeIdentifier)
        guard let recognizer = SFSpeechRecognizer(locale: locale),
              recognizer.isAvailable else {
            throw AppleSpeechTranscriberError.recognizerUnavailable(
                localeIdentifier
            )
        }

        let request = SFSpeechAudioBufferRecognitionRequest()
        request.shouldReportPartialResults = true
        request.addsPunctuation = true
        request.taskHint = .dictation
        request.contextualStrings = ["Relay", "Codex"]
        request.requiresOnDeviceRecognition =
            recognizer.supportsOnDeviceRecognition

        let pair =
            AsyncThrowingStream<RecognitionResult, any Error>
                .makeStream(bufferingPolicy: .unbounded)
        let continuation = pair.continuation
        let task = recognizer.recognitionTask(
            with: request
        ) { result, error in
            if let result {
                continuation.yield(
                    RecognitionResult(
                        text: result.bestTranscription.formattedString,
                        isFinal: result.isFinal
                    )
                )
                if result.isFinal {
                    continuation.finish()
                }
            }
            if let error {
                continuation.finish(throwing: error)
            }
        }

        self.recognizer = recognizer
        recognitionRequest = request
        recognitionTask = task
        resultStream = pair.stream
        resultContinuation = continuation
    }

    public func append(_ chunk: RelayAudioChunk) throws {
        guard let recognitionRequest else {
            throw AppleSpeechTranscriberError.notRunning
        }
        recognitionRequest.append(try Self.audioBuffer(from: chunk))
    }

    public func finish() async throws -> String {
        guard let recognitionRequest, let resultStream else {
            throw AppleSpeechTranscriberError.notRunning
        }
        recognitionRequest.endAudio()

        do {
            let transcript = try await Self.finalTranscript(
                from: resultStream,
                timeout: transcriptionTimeout
            )
            cleanUp()
            return transcript
        } catch {
            cleanUp()
            throw AppleSpeechTranscriberError.classify(error) ?? error
        }
    }

    public func cancel() {
        cleanUp()
    }

    private func ensureAuthorization() async throws {
        let status: SFSpeechRecognizerAuthorizationStatus
        switch SFSpeechRecognizer.authorizationStatus() {
        case .notDetermined:
            status = await withCheckedContinuation { continuation in
                SFSpeechRecognizer.requestAuthorization {
                    continuation.resume(returning: $0)
                }
            }
        case let existing:
            status = existing
        }

        switch status {
        case .authorized:
            return
        case .denied:
            throw AppleSpeechTranscriberError.permissionDenied
        case .restricted:
            throw AppleSpeechTranscriberError.permissionRestricted
        case .notDetermined:
            throw AppleSpeechTranscriberError.permissionDenied
        @unknown default:
            throw AppleSpeechTranscriberError.permissionRestricted
        }
    }

    private func cleanUp() {
        recognitionRequest?.endAudio()
        recognitionTask?.cancel()
        resultContinuation?.finish()
        recognitionTask = nil
        recognitionRequest = nil
        recognizer = nil
        resultStream = nil
        resultContinuation = nil
    }

    private static func finalTranscript(
        from stream:
            AsyncThrowingStream<RecognitionResult, any Error>,
        timeout: Duration
    ) async throws -> String {
        try await withThrowingTaskGroup(of: String.self) { group in
            group.addTask {
                var latest = ""
                for try await result in stream {
                    let text = result.text.trimmingCharacters(
                        in: .whitespacesAndNewlines
                    )
                    if !text.isEmpty {
                        latest = text
                    }
                    if result.isFinal {
                        guard !latest.isEmpty else {
                            throw AppleSpeechTranscriberError.noSpeech
                        }
                        return latest
                    }
                }
                guard !latest.isEmpty else {
                    throw AppleSpeechTranscriberError.noSpeech
                }
                return latest
            }
            group.addTask {
                try await Task.sleep(for: timeout)
                throw AppleSpeechTranscriberError.timedOut
            }

            guard let transcript = try await group.next() else {
                throw AppleSpeechTranscriberError.noSpeech
            }
            group.cancelAll()
            return transcript
        }
    }

    private static func audioBuffer(
        from chunk: RelayAudioChunk
    ) throws -> AVAudioPCMBuffer {
        guard chunk.sampleRate > 0,
              chunk.numChannels > 0,
              let data = Data(base64Encoded: chunk.data),
              !data.isEmpty,
              let format = AVAudioFormat(
                  commonFormat: .pcmFormatInt16,
                  sampleRate: Double(chunk.sampleRate),
                  channels: AVAudioChannelCount(chunk.numChannels),
                  interleaved: true
              ) else {
            throw AppleSpeechTranscriberError.invalidAudio
        }

        let bytesPerFrame = Int(chunk.numChannels) * 2
        guard bytesPerFrame > 0,
              data.count.isMultiple(of: bytesPerFrame) else {
            throw AppleSpeechTranscriberError.invalidAudio
        }
        let derivedFrames = data.count / bytesPerFrame
        let frameCount = chunk.samplesPerChannel.map(Int.init)
            ?? derivedFrames
        guard frameCount > 0,
              frameCount == derivedFrames,
              frameCount <= Int(UInt32.max),
              let buffer = AVAudioPCMBuffer(
                  pcmFormat: format,
                  frameCapacity: AVAudioFrameCount(frameCount)
              ) else {
            throw AppleSpeechTranscriberError.invalidAudio
        }

        buffer.frameLength = AVAudioFrameCount(frameCount)
        guard let destination = buffer.mutableAudioBufferList
            .pointee.mBuffers.mData else {
            throw AppleSpeechTranscriberError.invalidAudio
        }
        data.copyBytes(
            to: destination.assumingMemoryBound(to: UInt8.self),
            count: data.count
        )
        return buffer
    }
}

private struct RecognitionResult: Sendable {
    let text: String
    let isFinal: Bool
}
