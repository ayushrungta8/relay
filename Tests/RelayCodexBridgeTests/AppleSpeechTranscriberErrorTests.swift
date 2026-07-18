import Foundation
import RelayCodexBridge
import RelayVoice
import Testing

struct AppleSpeechTranscriberErrorTests {
    @Test
    func classifiesDisabledDictationWithoutPrivatePreferenceReads() {
        let source = NSError(
            domain: "kLSRErrorDomain",
            code: 201,
            userInfo: [
                NSLocalizedDescriptionKey:
                    "Siri and Dictation are disabled",
            ]
        )

        let error = AppleSpeechTranscriberError.classify(source)

        #expect(error == .dictationDisabled)
        #expect(error?.voiceReadinessState == .dictationDisabled)
    }

    @Test
    func classifiesOfflineRecognition() {
        let source = URLError(.notConnectedToInternet)

        let error = AppleSpeechTranscriberError.classify(source)

        #expect(error == .networkUnavailable)
        #expect(error?.voiceReadinessState == .networkUnavailable)
    }

    @Test
    func leavesUnknownErrorsUnclassified() {
        let source = NSError(domain: "Fixture", code: 7)

        #expect(AppleSpeechTranscriberError.classify(source) == nil)
    }
}
