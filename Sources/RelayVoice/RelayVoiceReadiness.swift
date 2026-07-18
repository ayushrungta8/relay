@preconcurrency import AVFoundation
import Foundation
@preconcurrency import Speech

public enum RelayVoicePermissionStatus: Equatable, Sendable {
    case notDetermined
    case authorized
    case denied
    case restricted
}

public enum RelayVoiceReadinessState: Equatable, Sendable {
    case ready
    case needsMicrophoneRequest
    case needsSpeechRecognitionRequest
    case microphoneDenied
    case microphoneRestricted
    case speechRecognitionDenied
    case speechRecognitionRestricted
    case dictationDisabled
    case unsupportedLocale(String)
    case recognizerUnavailable(String)
    case microphoneUnavailable
    case networkUnavailable
}

@MainActor
public protocol RelayVoiceReadinessChecking: AnyObject {
    func currentState() -> RelayVoiceReadinessState
    func requestRequiredPermissions() async -> RelayVoiceReadinessState
}

@MainActor
public final class RelayVoiceReadinessService:
    RelayVoiceReadinessChecking
{
    private let localeIdentifier: String
    private let microphoneStatus: () -> RelayVoicePermissionStatus
    private let requestMicrophone: () async -> RelayVoicePermissionStatus
    private let speechStatus: () -> RelayVoicePermissionStatus
    private let requestSpeech: () async -> RelayVoicePermissionStatus
    private let supportedLocaleIdentifiers: () -> Set<String>
    private let recognizerAvailable: (String) -> Bool

    public convenience init(
        localeIdentifier: String = Locale.current.identifier
    ) {
        self.init(
            localeIdentifier: localeIdentifier,
            microphoneStatus: {
                switch AVAudioApplication.shared.recordPermission {
                case .undetermined:
                    .notDetermined
                case .granted:
                    .authorized
                case .denied:
                    AVCaptureDevice.authorizationStatus(for: .audio)
                        == .restricted
                        ? .restricted
                        : .denied
                @unknown default:
                    .restricted
                }
            },
            requestMicrophone: {
                await AVAudioApplication.requestRecordPermission()
                    ? .authorized
                    : .denied
            },
            speechStatus: {
                Self.permissionStatus(
                    from: SFSpeechRecognizer.authorizationStatus()
                )
            },
            requestSpeech: {
                await withCheckedContinuation { continuation in
                    SFSpeechRecognizer.requestAuthorization { status in
                        continuation.resume(
                            returning: Self.permissionStatus(from: status)
                        )
                    }
                }
            },
            supportedLocaleIdentifiers: {
                Set(SFSpeechRecognizer.supportedLocales().map(\.identifier))
            },
            recognizerAvailable: { localeIdentifier in
                SFSpeechRecognizer(
                    locale: Locale(identifier: localeIdentifier)
                )?.isAvailable == true
            }
        )
    }

    init(
        localeIdentifier: String,
        microphoneStatus: @escaping () -> RelayVoicePermissionStatus,
        requestMicrophone:
            @escaping () async -> RelayVoicePermissionStatus,
        speechStatus: @escaping () -> RelayVoicePermissionStatus,
        requestSpeech: @escaping () async -> RelayVoicePermissionStatus,
        supportedLocaleIdentifiers: @escaping () -> Set<String>,
        recognizerAvailable: @escaping (String) -> Bool
    ) {
        self.localeIdentifier = localeIdentifier
        self.microphoneStatus = microphoneStatus
        self.requestMicrophone = requestMicrophone
        self.speechStatus = speechStatus
        self.requestSpeech = requestSpeech
        self.supportedLocaleIdentifiers = supportedLocaleIdentifiers
        self.recognizerAvailable = recognizerAvailable
    }

    public func currentState() -> RelayVoiceReadinessState {
        switch microphoneStatus() {
        case .notDetermined:
            return .needsMicrophoneRequest
        case .denied:
            return .microphoneDenied
        case .restricted:
            return .microphoneRestricted
        case .authorized:
            break
        }

        switch speechStatus() {
        case .notDetermined:
            return .needsSpeechRecognitionRequest
        case .denied:
            return .speechRecognitionDenied
        case .restricted:
            return .speechRecognitionRestricted
        case .authorized:
            break
        }

        guard supportedLocaleIdentifiers().contains(localeIdentifier) else {
            return .unsupportedLocale(localeIdentifier)
        }
        guard recognizerAvailable(localeIdentifier) else {
            return .recognizerUnavailable(localeIdentifier)
        }
        return .ready
    }

    public func requestRequiredPermissions() async
        -> RelayVoiceReadinessState
    {
        if currentState() == .needsMicrophoneRequest {
            let status = await requestMicrophone()
            switch status {
            case .denied:
                return .microphoneDenied
            case .restricted:
                return .microphoneRestricted
            case .notDetermined:
                return .needsMicrophoneRequest
            case .authorized:
                break
            }
        }

        if currentState() == .needsSpeechRecognitionRequest {
            let status = await requestSpeech()
            switch status {
            case .denied:
                return .speechRecognitionDenied
            case .restricted:
                return .speechRecognitionRestricted
            case .notDetermined:
                return .needsSpeechRecognitionRequest
            case .authorized:
                break
            }
        }

        return currentState()
    }

    private nonisolated static func permissionStatus(
        from status: SFSpeechRecognizerAuthorizationStatus
    ) -> RelayVoicePermissionStatus {
        switch status {
        case .notDetermined:
            .notDetermined
        case .authorized:
            .authorized
        case .denied:
            .denied
        case .restricted:
            .restricted
        @unknown default:
            .restricted
        }
    }
}
