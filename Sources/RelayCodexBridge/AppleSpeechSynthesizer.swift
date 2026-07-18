@preconcurrency import AVFoundation
import Foundation

/// Speaks Relay's answers aloud using the built-in macOS speech
/// synthesizer.
///
/// This is the text-to-speech counterpart to ``AppleSpeechTranscriber``:
/// both lean on Apple's on-device frameworks, so a spoken answer needs no
/// network round-trip, API key, or per-character billing, and it honors
/// the system voice the user picked in System Settings.
public protocol RelaySpeechSynthesizing: Sendable {
    /// Speaks `text`, interrupting any utterance already in flight.
    func speak(_ text: String) async

    /// Immediately stops any in-progress speech (barge-in).
    func stop() async
}

/// Runs on the main actor because `AVSpeechSynthesizer` and its delegate
/// callbacks are main-thread bound (mirroring Pointee's speech driver). The
/// `onSpeakingChange` handler fires `true` when an utterance begins and
/// `false` when it finishes or is cancelled, so the UI can show a "Speaking"
/// state.
@MainActor
public final class AppleSpeechSynthesizer:
    NSObject,
    RelaySpeechSynthesizing,
    @preconcurrency AVSpeechSynthesizerDelegate
{
    private let synthesizer: AVSpeechSynthesizer
    private var explicitVoiceIdentifier: String?
    private var isEnabled: Bool
    private let rate: Float
    private let pitchMultiplier: Float
    private let onSpeakingChange: @MainActor @Sendable (Bool) -> Void

    /// - Parameters:
    ///   - voiceIdentifier: An explicit `AVSpeechSynthesisVoice`
    ///     identifier. When `nil` (the default) Relay speaks with the voice
    ///     the user selected in System Settings, resolved per-utterance via
    ///     ``SystemSpeechVoiceResolver`` — not AVFoundation's basic default.
    ///   - rate: Speech rate; defaults to the system default.
    ///   - pitchMultiplier: Voice pitch; `1.0` is natural.
    ///   - synthesizer: Injection seam for tests.
    ///   - onSpeakingChange: Notified when speech starts (`true`) and ends
    ///     (`false`).
    public init(
        voiceIdentifier: String? = nil,
        isEnabled: Bool = true,
        rate: Float = AVSpeechUtteranceDefaultSpeechRate,
        pitchMultiplier: Float = 1.0,
        synthesizer: AVSpeechSynthesizer = AVSpeechSynthesizer(),
        onSpeakingChange: @escaping @MainActor @Sendable (Bool) -> Void = { _ in }
    ) {
        self.synthesizer = synthesizer
        explicitVoiceIdentifier = voiceIdentifier
        self.isEnabled = isEnabled
        self.rate = rate
        self.pitchMultiplier = pitchMultiplier
        self.onSpeakingChange = onSpeakingChange
        super.init()
        synthesizer.delegate = self
    }

    public func speak(_ text: String) {
        guard isEnabled else { return }
        let trimmed = text.trimmingCharacters(
            in: .whitespacesAndNewlines
        )
        guard !trimmed.isEmpty else { return }

        if synthesizer.isSpeaking {
            synthesizer.stopSpeaking(at: .immediate)
        }

        let utterance = AVSpeechUtterance(string: trimmed)
        utterance.rate = rate
        utterance.pitchMultiplier = pitchMultiplier
        if let voice = resolvedVoice() {
            utterance.voice = voice
        }
        synthesizer.speak(utterance)
    }

    public func configure(
        enabled: Bool,
        voiceIdentifier: String?
    ) {
        isEnabled = enabled
        explicitVoiceIdentifier = voiceIdentifier
        if !enabled {
            stop()
        }
    }

    public func stop() {
        guard synthesizer.isSpeaking else { return }
        synthesizer.stopSpeaking(at: .immediate)
    }

    private func resolvedVoice() -> AVSpeechSynthesisVoice? {
        let identifier = explicitVoiceIdentifier
            ?? SystemSpeechVoiceResolver.configuredVoiceIdentifier()
        guard let identifier else { return nil }
        return AVSpeechSynthesisVoice(identifier: identifier)
    }

    // MARK: - AVSpeechSynthesizerDelegate

    public func speechSynthesizer(
        _ synthesizer: AVSpeechSynthesizer,
        didStart utterance: AVSpeechUtterance
    ) {
        onSpeakingChange(true)
    }

    public func speechSynthesizer(
        _ synthesizer: AVSpeechSynthesizer,
        didFinish utterance: AVSpeechUtterance
    ) {
        onSpeakingChange(false)
    }

    public func speechSynthesizer(
        _ synthesizer: AVSpeechSynthesizer,
        didCancel utterance: AVSpeechUtterance
    ) {
        onSpeakingChange(false)
    }
}
