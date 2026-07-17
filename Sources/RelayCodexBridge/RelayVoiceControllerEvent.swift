import Foundation

public enum RelayVoiceControllerEvent: Sendable, Equatable {
    case transcript(String)
    case answerUpdate(String)
    case answer(String)
    case failed(String)
}
