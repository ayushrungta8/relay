import RelayVoice

enum RelayVoiceSettingsDestination: Equatable, Sendable {
    case microphone
    case speechRecognition
    case dictation
}

enum RelayVoiceSetupAction: Equatable, Sendable {
    case requestPermissions
    case openSettings(RelayVoiceSettingsDestination)
}

struct RelayVoiceSetupPresentation: Equatable, Sendable {
    let title: String
    let message: String
    let primaryAction: RelayVoiceSetupAction?
    let primaryActionTitle: String?
    let diagnostic: String?

    init(
        title: String,
        message: String,
        primaryAction: RelayVoiceSetupAction? = nil,
        primaryActionTitle: String? = nil,
        diagnostic: String? = nil
    ) {
        self.title = title
        self.message = message
        self.primaryAction = primaryAction
        self.primaryActionTitle = primaryActionTitle
        self.diagnostic = diagnostic
    }

    init(state: RelayVoiceReadinessState) {
        switch state {
        case .ready:
            self = .ready
        case .needsMicrophoneRequest,
             .needsSpeechRecognitionRequest:
            self.init(
                title: "Set up voice",
                message: "Relay needs Microphone and Speech Recognition access before Option-Space can listen.",
                primaryAction: .requestPermissions,
                primaryActionTitle: "Continue"
            )
        case .microphoneDenied:
            self.init(
                title: "Microphone access is off",
                message: "Allow Relay to use the microphone while you hold Option-Space.",
                primaryAction: .openSettings(.microphone),
                primaryActionTitle: "Open Microphone Settings"
            )
        case .microphoneRestricted:
            self.init(
                title: "Microphone access is restricted",
                message: "Screen Time or device management may prevent Relay from using this Mac’s microphone.",
                primaryAction: .openSettings(.microphone),
                primaryActionTitle: "Open Microphone Settings"
            )
        case .speechRecognitionDenied:
            self.init(
                title: "Speech Recognition is off",
                message: "Allow Relay to turn your spoken command into text.",
                primaryAction: .openSettings(.speechRecognition),
                primaryActionTitle: "Open Speech Recognition Settings"
            )
        case .speechRecognitionRestricted:
            self.init(
                title: "Speech Recognition is restricted",
                message: "Screen Time or device management may prevent speech recognition on this Mac.",
                primaryAction: .openSettings(.speechRecognition),
                primaryActionTitle: "Open Speech Recognition Settings"
            )
        case .dictationDisabled:
            self.init(
                title: "Turn on Dictation",
                message: "Enable Dictation in System Settings → Keyboard, then hold Option-Space again.",
                primaryAction: .openSettings(.dictation),
                primaryActionTitle: "Open Keyboard Settings"
            )
        case let .unsupportedLocale(locale):
            self.init(
                title: "Language isn’t supported",
                message: "Apple Speech doesn’t support Relay’s current locale: \(locale). Enable a supported Dictation language in Keyboard Settings.",
                primaryAction: .openSettings(.dictation),
                primaryActionTitle: "Open Keyboard Settings"
            )
        case let .recognizerUnavailable(locale):
            self.init(
                title: "Speech Recognition is unavailable",
                message: "Apple Speech is not currently available for \(locale). Try again later."
            )
        case .microphoneUnavailable:
            self.init(
                title: "No microphone is available",
                message: "Connect or select a microphone, then hold Option-Space again."
            )
        case .networkUnavailable:
            self.init(
                title: "Speech Recognition needs a connection",
                message: "This language cannot currently recognize speech on device. Connect to the internet and try again."
            )
        }
    }

    static let ready = RelayVoiceSetupPresentation(
        title: "Voice is ready",
        message: "Hold Option-Space again to speak to Relay."
    )

    static func runtimeFailure(
        message: String,
        diagnostic: String? = nil
    ) -> RelayVoiceSetupPresentation {
        RelayVoiceSetupPresentation(
            title: "Voice couldn’t start",
            message: message,
            diagnostic: diagnostic
        )
    }
}
