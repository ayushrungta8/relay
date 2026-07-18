import Foundation
import RelayVoice
import Testing
@testable import RelayApp

@MainActor
struct RelayVoiceSetupPresentationTests {
    @Test
    func deniedMicrophoneOffersItsPrivacyPane() {
        let presentation = RelayVoiceSetupPresentation(
            state: .microphoneDenied
        )

        #expect(presentation.title == "Microphone access is off")
        #expect(
            presentation.message
                == "Allow Relay to use the microphone while you hold Option-Space."
        )
        #expect(
            presentation.primaryAction
                == .openSettings(.microphone)
        )
        #expect(
            presentation.primaryActionTitle
                == "Open Microphone Settings"
        )
    }

    @Test
    func disabledDictationOffersKeyboardSettings() {
        let presentation = RelayVoiceSetupPresentation(
            state: .dictationDisabled
        )

        #expect(
            presentation.primaryAction
                == .openSettings(.dictation)
        )
        #expect(presentation.primaryActionTitle == "Open Keyboard Settings")
    }

    @Test
    func permissionRequestsExplainBothNativePrompts() {
        let presentation = RelayVoiceSetupPresentation(
            state: .needsMicrophoneRequest
        )

        #expect(presentation.title == "Set up voice")
        #expect(presentation.primaryAction == .requestPermissions)
        #expect(presentation.primaryActionTitle == "Continue")
    }

    @Test
    func settingsOpenerFallsBackWhenSpecificPaneIsRejected() {
        var opened: [URL] = []
        let opener = RelayVoiceSettingsOpener { url in
            opened.append(url)
            return opened.count == 2
        }

        #expect(opener.open(.dictation))
        #expect(opened.count == 2)
        #expect(
            opened[0].absoluteString
                == "x-apple.systempreferences:com.apple.Keyboard-Settings.extension"
        )
        #expect(opened[1].absoluteString == "x-apple.systempreferences:")
    }
}
