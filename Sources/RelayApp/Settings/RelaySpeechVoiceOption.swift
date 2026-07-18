import AVFoundation
import Foundation

struct RelaySpeechVoiceOption: Identifiable, Equatable {
    let id: String
    let name: String
    let language: String

    static var installed: [Self] {
        let voices = AVSpeechSynthesisVoice.speechVoices()
        let languageCode = Locale.current.language.languageCode?.identifier
        let local = voices.filter {
            guard let languageCode else { return true }
            return $0.language.hasPrefix(languageCode)
        }
        let candidates = local.isEmpty ? voices : local
        return candidates
            .map { Self(id: $0.identifier, name: $0.name, language: $0.language) }
            .sorted {
                $0.name.localizedCaseInsensitiveCompare($1.name)
                    == .orderedAscending
            }
    }
}
