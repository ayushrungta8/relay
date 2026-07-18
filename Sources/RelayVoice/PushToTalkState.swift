public enum PushToTalkState: Equatable, Sendable {
    case idle
    case listening
    case finishing
    case failed(RelayPushToTalkFailure)
}

public enum PushToTalkEvent: Equatable, Sendable {
    case pressed
    case released
    case cancelRequested
    case completed
    case failed(RelayPushToTalkFailure)
}

public enum PushToTalkEffect: Equatable, Sendable {
    case startListening
    case finishAndSend
    case cancel
}

public struct PushToTalkStateMachine: Sendable {
    public private(set) var state: PushToTalkState

    public init(state: PushToTalkState = .idle) {
        self.state = state
    }

    @discardableResult
    public mutating func send(
        _ event: PushToTalkEvent
    ) -> PushToTalkEffect? {
        switch (state, event) {
        case (.idle, .pressed), (.failed, .pressed):
            state = .listening
            return .startListening

        case (.listening, .released):
            state = .finishing
            return .finishAndSend

        case (.listening, .cancelRequested),
             (.finishing, .cancelRequested),
             (.failed, .cancelRequested):
            state = .finishing
            return .cancel

        case (.finishing, .completed):
            state = .idle
            return nil

        case (.listening, let .failed(message)),
             (.finishing, let .failed(message)):
            state = .failed(message)
            return nil

        default:
            return nil
        }
    }
}
