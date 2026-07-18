@testable import RelayVoice
import Testing

@MainActor
struct RelayVoiceReadinessTests {
    @Test
    func microphonePermissionComesBeforeSpeechPermission() async {
        let fixture = RelayVoiceReadinessFixture(
            microphone: .notDetermined,
            speech: .notDetermined
        )
        let service = fixture.makeService()

        #expect(service.currentState() == .needsMicrophoneRequest)
        #expect(await service.requestRequiredPermissions() == .ready)
        #expect(fixture.requests == [.microphone, .speechRecognition])
    }

    @Test
    func microphoneDenialStopsBeforeSpeechPrompt() async {
        let fixture = RelayVoiceReadinessFixture(
            microphone: .notDetermined,
            speech: .notDetermined,
            microphoneRequestResult: .denied
        )
        let service = fixture.makeService()

        #expect(
            await service.requestRequiredPermissions()
                == .microphoneDenied
        )
        #expect(fixture.requests == [.microphone])
    }

    @Test(arguments: [
        (
            RelayVoicePermissionStatus.denied,
            RelayVoiceReadinessState.microphoneDenied
        ),
        (.restricted, .microphoneRestricted),
    ])
    func reportsExistingMicrophoneBlockers(
        permission: RelayVoicePermissionStatus,
        expected: RelayVoiceReadinessState
    ) {
        let fixture = RelayVoiceReadinessFixture(
            microphone: permission,
            speech: .authorized
        )
        let service = fixture.makeService()

        #expect(service.currentState() == expected)
    }

    @Test(arguments: [
        (
            RelayVoicePermissionStatus.notDetermined,
            RelayVoiceReadinessState.needsSpeechRecognitionRequest
        ),
        (.denied, .speechRecognitionDenied),
        (.restricted, .speechRecognitionRestricted),
    ])
    func reportsSpeechPermissionStates(
        permission: RelayVoicePermissionStatus,
        expected: RelayVoiceReadinessState
    ) {
        let fixture = RelayVoiceReadinessFixture(
            microphone: .authorized,
            speech: permission
        )
        let service = fixture.makeService()

        #expect(service.currentState() == expected)
    }

    @Test
    func reportsUnsupportedAndUnavailableLocales() {
        let unsupportedFixture = RelayVoiceReadinessFixture(
            microphone: .authorized,
            speech: .authorized,
            localeIdentifier: "zz_ZZ",
            supportedLocaleIdentifiers: ["en_US"]
        )
        let unsupported = unsupportedFixture.makeService()
        #expect(
            unsupported.currentState()
                == .unsupportedLocale("zz_ZZ")
        )

        let unavailableFixture = RelayVoiceReadinessFixture(
            microphone: .authorized,
            speech: .authorized,
            recognizerAvailable: false
        )
        let unavailable = unavailableFixture.makeService()
        #expect(
            unavailable.currentState()
                == .recognizerUnavailable("en_US")
        )
    }
}

@MainActor
private final class RelayVoiceReadinessFixture {
    enum Request: Equatable {
        case microphone
        case speechRecognition
    }

    var microphone: RelayVoicePermissionStatus
    var speech: RelayVoicePermissionStatus
    let microphoneRequestResult: RelayVoicePermissionStatus
    let speechRequestResult: RelayVoicePermissionStatus
    let localeIdentifier: String
    let supportedLocaleIdentifiers: Set<String>
    let recognizerAvailable: Bool
    private(set) var requests: [Request] = []

    init(
        microphone: RelayVoicePermissionStatus,
        speech: RelayVoicePermissionStatus,
        microphoneRequestResult: RelayVoicePermissionStatus = .authorized,
        speechRequestResult: RelayVoicePermissionStatus = .authorized,
        localeIdentifier: String = "en_US",
        supportedLocaleIdentifiers: Set<String> = ["en_US"],
        recognizerAvailable: Bool = true
    ) {
        self.microphone = microphone
        self.speech = speech
        self.microphoneRequestResult = microphoneRequestResult
        self.speechRequestResult = speechRequestResult
        self.localeIdentifier = localeIdentifier
        self.supportedLocaleIdentifiers = supportedLocaleIdentifiers
        self.recognizerAvailable = recognizerAvailable
    }

    func makeService() -> RelayVoiceReadinessService {
        RelayVoiceReadinessService(
            localeIdentifier: localeIdentifier,
            microphoneStatus: { [unowned self] in microphone },
            requestMicrophone: { [unowned self] in
                requests.append(.microphone)
                microphone = microphoneRequestResult
                return microphoneRequestResult
            },
            speechStatus: { [unowned self] in speech },
            requestSpeech: { [unowned self] in
                requests.append(.speechRecognition)
                speech = speechRequestResult
                return speechRequestResult
            },
            supportedLocaleIdentifiers: {
                [unowned self] in supportedLocaleIdentifiers
            },
            recognizerAvailable: { [unowned self] _ in
                recognizerAvailable
            }
        )
    }
}
