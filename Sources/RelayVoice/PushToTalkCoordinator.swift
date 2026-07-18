import Foundation

@MainActor
public final class PushToTalkCoordinator {
    public var state: PushToTalkState {
        stateMachine.state
    }

    private let microphone: any RelayMicrophoneCapturing
    private let sink: any RelayRealtimeAudioSink
    private let onStateChange:
        @MainActor @Sendable (PushToTalkState) -> Void

    private var stateMachine = PushToTalkStateMachine()
    private var nextSessionID: UInt64 = 0
    private var activeSessionID: UInt64?
    private var sessionTask: Task<AudioSessionResult, Never>?
    private var termination: Termination?

    public init(
        microphone: any RelayMicrophoneCapturing,
        sink: any RelayRealtimeAudioSink,
        onStateChange: @escaping @MainActor @Sendable
            (PushToTalkState) -> Void = { _ in }
    ) {
        self.microphone = microphone
        self.sink = sink
        self.onStateChange = onStateChange
    }

    public func press() {
        guard send(.pressed) == .startListening else {
            return
        }

        do {
            let stream = try microphone.start()
            nextSessionID &+= 1
            let sessionID = nextSessionID
            let sink = sink
            let task = Task.detached(
                priority: .userInitiated
            ) {
                do {
                    try Task.checkCancellation()
                    try await sink.start()
                    try Task.checkCancellation()
                    for await chunk in stream {
                        try Task.checkCancellation()
                        try await sink.append(chunk)
                    }
                    return AudioSessionResult.completed
                } catch is CancellationError {
                    return AudioSessionResult.cancelled
                } catch {
                    return AudioSessionResult.failed(
                        RelayPushToTalkFailure(error: error)
                    )
                }
            }

            activeSessionID = sessionID
            sessionTask = task
            termination = nil

            Task { @MainActor [weak self] in
                let result = await task.value
                await self?.observe(
                    result,
                    forSession: sessionID
                )
            }
        } catch {
            microphone.stop()
            send(
                .failed(RelayPushToTalkFailure(error: error))
            )
        }
    }

    public func release() async {
        guard send(.released) == .finishAndSend,
              let sessionID = activeSessionID,
              let task = sessionTask else {
            return
        }

        termination = .sending
        microphone.stop()
        let result = await task.value

        guard activeSessionID == sessionID,
              termination == .sending else {
            return
        }

        switch result {
        case .completed:
            do {
                try await sink.finishAndSend()
                guard activeSessionID == sessionID,
                      termination == .sending else {
                    return
                }
                clearSession()
                send(.completed)
            } catch {
                await failSession(
                    RelayPushToTalkFailure(error: error),
                    sessionID: sessionID,
                    microphoneIsStopped: true
                )
            }

        case .cancelled:
            await failSession(
                RelayPushToTalkFailure(
                    message: "Push-to-talk audio streaming was cancelled."
                ),
                sessionID: sessionID,
                microphoneIsStopped: true
            )

        case let .failed(message):
            await failSession(
                message,
                sessionID: sessionID,
                microphoneIsStopped: true
            )
        }
    }

    public func cancel() async {
        guard termination != .cancelling,
              send(.cancelRequested) == .cancel else {
            return
        }

        guard let sessionID = activeSessionID else {
            send(.completed)
            return
        }

        termination = .cancelling
        microphone.stop()
        sessionTask?.cancel()
        await sink.cancel()
        _ = await sessionTask?.value

        guard activeSessionID == sessionID,
              termination == .cancelling else {
            return
        }

        clearSession()
        send(.completed)
    }

    private func observe(
        _ result: AudioSessionResult,
        forSession sessionID: UInt64
    ) async {
        guard activeSessionID == sessionID,
              termination == nil else {
            return
        }

        switch result {
        case .completed:
            await failSession(
                RelayPushToTalkFailure(
                    message: "Microphone capture ended before release."
                ),
                sessionID: sessionID,
                microphoneIsStopped: false
            )
        case .cancelled:
            await failSession(
                RelayPushToTalkFailure(
                    message: "Push-to-talk audio streaming was cancelled."
                ),
                sessionID: sessionID,
                microphoneIsStopped: false
            )
        case let .failed(message):
            await failSession(
                message,
                sessionID: sessionID,
                microphoneIsStopped: false
            )
        }
    }

    private func failSession(
        _ failure: RelayPushToTalkFailure,
        sessionID: UInt64,
        microphoneIsStopped: Bool
    ) async {
        guard activeSessionID == sessionID else { return }

        termination = .failing
        if !microphoneIsStopped {
            microphone.stop()
        }
        sessionTask?.cancel()
        await sink.cancel()

        guard activeSessionID == sessionID,
              termination == .failing else {
            return
        }

        clearSession()
        send(.failed(failure))
    }

    private func clearSession() {
        activeSessionID = nil
        sessionTask = nil
        termination = nil
    }

    @discardableResult
    private func send(
        _ event: PushToTalkEvent
    ) -> PushToTalkEffect? {
        let previousState = stateMachine.state
        let effect = stateMachine.send(event)
        if stateMachine.state != previousState {
            onStateChange(stateMachine.state)
        }
        return effect
    }
}

private enum AudioSessionResult: Sendable {
    case completed
    case cancelled
    case failed(RelayPushToTalkFailure)
}

private enum Termination: Sendable {
    case sending
    case cancelling
    case failing
}
