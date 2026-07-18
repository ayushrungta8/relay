import AppKit
import Foundation

struct RelayVoiceSettingsOpener {
    private let openURL: (URL) -> Bool

    init(
        openURL: @escaping (URL) -> Bool = NSWorkspace.shared.open
    ) {
        self.openURL = openURL
    }

    @discardableResult
    func open(_ destination: RelayVoiceSettingsDestination) -> Bool {
        let destinationURL = switch destination {
        case .microphone:
            "x-apple.systempreferences:com.apple.preference.security?Privacy_Microphone"
        case .speechRecognition:
            "x-apple.systempreferences:com.apple.preference.security?Privacy_SpeechRecognition"
        case .dictation:
            "x-apple.systempreferences:com.apple.Keyboard-Settings.extension"
        }

        if let url = URL(string: destinationURL), openURL(url) {
            return true
        }
        guard let fallback = URL(string: "x-apple.systempreferences:") else {
            return false
        }
        return openURL(fallback)
    }
}
