import AVFoundation
import AppKit

/// Resolves the voice the user actually selected in macOS System Settings.
///
/// `AVSpeechSynthesizer`'s default (`nil`) voice does not reliably follow the
/// system voice chosen in Settings — it tends to fall back to a basic compact
/// voice, which sounds noticeably worse than the Siri/premium voice a user
/// picked. AppKit's `NSSpeechSynthesizer.defaultVoice` exposes that exact
/// choice; AVFoundation still performs the synthesis. Adopted from the Pointee
/// project's `SystemSpeechVoiceResolver`.
enum SystemSpeechVoiceResolver {
    @MainActor
    static func configuredVoiceIdentifier() -> String? {
        let identifier = NSSpeechSynthesizer.defaultVoice.rawValue
        // Only use it when AVFoundation recognizes the identifier; otherwise
        // let AVSpeech fall back to its own default.
        guard AVSpeechSynthesisVoice(identifier: identifier) != nil else {
            return nil
        }
        return identifier
    }
}
