import Foundation
import RelayVoice

public enum AppleSpeechCommandSinkError:
    Error,
    Sendable,
    Equatable
{
    case invalidState
    case emptyTranscript
}

extension AppleSpeechCommandSinkError: LocalizedError {
    public var errorDescription: String? {
        switch self {
        case .invalidState:
            "Relay voice is already busy."
        case .emptyTranscript:
            "Relay did not hear a spoken command."
        }
    }
}

public actor AppleSpeechCommandSink: RelayRealtimeAudioSink {
    private let transcriber: any RelaySpeechTranscribing
    private let commandHandler: any RelayCommandHandling
    private let onEvent:
        @Sendable (RelayVoiceControllerEvent) async -> Void

    private var state: State = .idle
    private var nextSessionID: UInt64 = 0
    private var activeSessionID: UInt64?

    public init(
        transcriber: any RelaySpeechTranscribing = AppleSpeechTranscriber(),
        commandHandler: any RelayCommandHandling,
        onEvent: @escaping @Sendable
            (RelayVoiceControllerEvent) async -> Void = { _ in }
    ) {
        self.transcriber = transcriber
        self.commandHandler = commandHandler
        self.onEvent = onEvent
    }

    public func start() async throws {
        guard state == .idle else {
            throw AppleSpeechCommandSinkError.invalidState
        }
        nextSessionID &+= 1
        let sessionID = nextSessionID
        activeSessionID = sessionID
        state = .starting

        do {
            try await transcriber.start()
            guard activeSessionID == sessionID else {
                await transcriber.cancel()
                throw CancellationError()
            }
            state = .transcribing
        } catch {
            if activeSessionID == sessionID {
                activeSessionID = nil
                state = .idle
                if !(error is CancellationError) {
                    await onEvent(.failed(error.localizedDescription))
                }
            }
            throw error
        }
    }

    public func append(_ chunk: RelayAudioChunk) async throws {
        guard state == .transcribing else {
            throw AppleSpeechCommandSinkError.invalidState
        }
        try await transcriber.append(chunk)
    }

    public func finishAndSend() async throws {
        guard state == .transcribing,
              let sessionID = activeSessionID else {
            throw AppleSpeechCommandSinkError.invalidState
        }
        state = .finishing

        do {
            let transcript = try await transcriber.finish()
                .trimmingCharacters(in: .whitespacesAndNewlines)
            try ensureActive(sessionID)
            guard !transcript.isEmpty else {
                throw AppleSpeechCommandSinkError.emptyTranscript
            }

            await onEvent(.transcript(transcript))
            try ensureActive(sessionID)
            let answer = try await commandHandler.submit(transcript)
            try ensureActive(sessionID)
            activeSessionID = nil
            state = .idle
            await onEvent(.answer(answer))
        } catch {
            if activeSessionID == sessionID {
                activeSessionID = nil
                await transcriber.cancel()
                state = .idle
                if !(error is CancellationError) {
                    await onEvent(.failed(error.localizedDescription))
                }
            }
            throw error
        }
    }

    public func cancel() async {
        guard state != .idle else { return }
        activeSessionID = nil
        state = .idle
        await transcriber.cancel()
    }

    private func ensureActive(_ sessionID: UInt64) throws {
        guard activeSessionID == sessionID else {
            throw CancellationError()
        }
    }
}

private enum State: Sendable {
    case idle
    case starting
    case transcribing
    case finishing
}
