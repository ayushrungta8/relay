import Foundation

public enum RelayVoiceControllerEvent: Sendable, Equatable {
    case transcript(String)
    case answerUpdate(String)
    case answer(String)
    /// Relay started (`true`) or stopped (`false`) speaking the answer aloud.
    case speaking(Bool)
    case failed(String)
}
