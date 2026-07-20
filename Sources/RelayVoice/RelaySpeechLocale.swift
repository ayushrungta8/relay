import Foundation
@preconcurrency import Speech

public enum RelaySpeechLocale {
    public static var currentIdentifier: String {
        identifier(
            systemRecognizerLocaleIdentifier:
                SFSpeechRecognizer()?.locale.identifier,
            preferredLanguages: Locale.preferredLanguages,
            fallbackLocaleIdentifier: Locale.current.identifier
        )
    }

    public static func identifier(
        systemRecognizerLocaleIdentifier: String?,
        preferredLanguages: [String],
        fallbackLocaleIdentifier: String
    ) -> String {
        let source = systemRecognizerLocaleIdentifier
            ?? preferredLanguages.first
            ?? fallbackLocaleIdentifier
        let baseIdentifier = source.split(
            separator: "@",
            maxSplits: 1
        ).first.map(String.init) ?? source
        return baseIdentifier.replacing("_", with: "-")
    }
}
