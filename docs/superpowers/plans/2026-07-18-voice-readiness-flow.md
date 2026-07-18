# Relay Voice Readiness Flow Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a demand-driven voice setup popup that requests Relay's voice permissions, explains system blockers, and starts recording only on a fresh Option-Space press after readiness succeeds.

**Architecture:** `RelayVoice` will own explicit readiness and typed failure values plus a platform-backed permission service. `RelayCodexBridge` will classify Apple Speech failures, while `RelayAppModel` will gate push-to-talk and expose a small presentation model rendered as an expanded notch overlay. Platform permission checks, prompt requests, and Settings opening remain injectable for deterministic tests.

**Tech Stack:** Swift 6.2, Swift Package Manager, SwiftUI, AppKit, AVFoundation, Speech, Carbon, Swift Testing.

## Global Constraints

- Support macOS 15.0 and later.
- Show voice setup only after a voice attempt; never block ordinary launch, text commands, or task monitoring.
- Request Microphone before Speech Recognition and never stack native permission prompts.
- Never continue the original shortcut attempt after showing setup UI, a native prompt, or System Settings.
- Never request Accessibility or Input Monitoring for Option-Space.
- Do not read private macOS preference domains to inspect Dictation.
- Do not automatically begin recording after a permission dialog closes.
- Use public AVFoundation and Speech authorization APIs.
- Keep actionable failures out of the composer's one-line 116-point status region.
- Preserve existing push-to-talk audio capture and controller submission behavior once readiness is `ready`.

---

## File Map

- Create `Sources/RelayVoice/RelayVoiceReadiness.swift`: readiness states, typed failure metadata, checker protocol, and production permission/recognizer service.
- Modify `Sources/RelayVoice/PushToTalkState.swift`: carry a typed `RelayPushToTalkFailure` instead of a bare string.
- Modify `Sources/RelayVoice/PushToTalkCoordinator.swift`: preserve readiness metadata while converting thrown errors into push-to-talk state.
- Modify `Sources/RelayVoice/AVAudioEngineMicrophoneCapture.swift`: expose microphone permission and input failures as readiness blockers.
- Modify `Package.swift`: link `Speech` into `RelayVoice`.
- Create `Tests/RelayVoiceTests/RelayVoiceReadinessTests.swift`: readiness ordering and sequential request tests.
- Modify `Tests/RelayVoiceTests/PushToTalkCoordinatorTests.swift`: typed failure propagation tests.
- Modify `Sources/RelayCodexBridge/AppleSpeechTranscriber.swift`: classify Dictation-disabled and network-dependent failures.
- Create `Tests/RelayCodexBridgeTests/AppleSpeechTranscriberErrorTests.swift`: stable error classification tests.
- Create `Sources/RelayApp/Voice/RelayVoiceSetupPresentation.swift`: user-facing setup copy and action mapping.
- Create `Sources/RelayApp/Voice/RelayVoiceSettingsOpener.swift`: injectable Settings destinations and fallback.
- Create `Sources/RelayApp/Voice/RelayVoiceSetupView.swift`: fully readable notch-native setup overlay.
- Modify `Sources/RelayApp/RelayAppModel.swift`: gate shortcut presses, request permissions, and publish setup state.
- Modify `Sources/RelayApp/Notch/RelayNotchPanelHost.swift`: wire setup actions and request expansion.
- Modify `Sources/RelayApp/Activity/RelayNotchRootView.swift`: render the setup overlay.
- Modify `Sources/RelayApp/Composer/RelayCommandComposerView.swift`: reserve the compact status label for transient states.
- Modify `Tests/RelayAppTests/RelayAppModelTests.swift`: verify voice gating and fresh-press behavior.
- Create `Tests/RelayAppTests/RelayVoiceSetupPresentationTests.swift`: copy/action mapping and Settings routing tests.

---

### Task 1: Build the Voice Readiness Service

**Files:**
- Create: `Sources/RelayVoice/RelayVoiceReadiness.swift`
- Modify: `Package.swift`
- Create: `Tests/RelayVoiceTests/RelayVoiceReadinessTests.swift`

**Interfaces:**
- Consumes: `AVAudioApplication.recordPermission`, `AVAudioApplication.requestRecordPermission()`, `SFSpeechRecognizer.authorizationStatus()`, `SFSpeechRecognizer.requestAuthorization(_:)`, `SFSpeechRecognizer.supportedLocales()`, and `SFSpeechRecognizer.isAvailable`.
- Produces: `RelayVoiceReadinessState`, `RelayVoiceReadinessChecking.currentState()`, and `RelayVoiceReadinessChecking.requestRequiredPermissions()`.

- [ ] **Step 1: Write failing readiness tests**

Create `Tests/RelayVoiceTests/RelayVoiceReadinessTests.swift` with table-driven checks for ordering and prompt behavior:

```swift
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
            microphoneRequestResult: false
        )
        let service = fixture.makeService()

        #expect(
            await service.requestRequiredPermissions()
                == .microphoneDenied
        )
        #expect(fixture.requests == [.microphone])
    }

    @Test(arguments: [
        (RelayVoicePermissionStatus.denied, RelayVoiceReadinessState.microphoneDenied),
        (.restricted, .microphoneRestricted),
    ])
    func reportsExistingMicrophoneBlockers(
        permission: RelayVoicePermissionStatus,
        expected: RelayVoiceReadinessState
    ) {
        let service = RelayVoiceReadinessFixture(
            microphone: permission,
            speech: .authorized
        ).makeService()

        #expect(service.currentState() == expected)
    }

    @Test
    func reportsUnsupportedAndUnavailableLocales() {
        let unsupported = RelayVoiceReadinessFixture(
            microphone: .authorized,
            speech: .authorized,
            localeIdentifier: "zz_ZZ",
            supportedLocaleIdentifiers: ["en_US"]
        ).makeService()
        #expect(unsupported.currentState() == .unsupportedLocale("zz_ZZ"))

        let unavailable = RelayVoiceReadinessFixture(
            microphone: .authorized,
            speech: .authorized,
            recognizerAvailable: false
        ).makeService()
        #expect(unavailable.currentState() == .recognizerUnavailable("en_US"))
    }
}
```

The same test file defines a mutable `@MainActor`
`RelayVoiceReadinessFixture`. Its `makeService()` passes closures reading the
fixture's permission fields into the service; its request closures append
`.microphone` or `.speechRecognition`, update the corresponding status from the
configured Boolean result, and return that result. Its locale closures return
`localeIdentifier`, `supportedLocaleIdentifiers`, and `recognizerAvailable`.

- [ ] **Step 2: Run the focused test and verify the missing types fail compilation**

Run:

```bash
swift test --filter RelayVoiceReadinessTests
```

Expected: compilation fails because `RelayVoiceReadinessState` and
`RelayVoiceReadinessService` do not exist.

- [ ] **Step 3: Implement the readiness domain and platform service**

Create `Sources/RelayVoice/RelayVoiceReadiness.swift` with these public
interfaces and ordered behavior:

```swift
@preconcurrency import AVFoundation
@preconcurrency import Speech
import Foundation

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
    public convenience init(localeIdentifier: String = Locale.current.identifier)
    public func currentState() -> RelayVoiceReadinessState
    public func requestRequiredPermissions() async -> RelayVoiceReadinessState
}
```

The designated internal initializer accepts closures for microphone status,
speech status, both async request operations, locale support, and recognizer
availability. `currentState()` checks Microphone, then Speech Recognition, then
locale support, then recognizer availability. `requestRequiredPermissions()`
requests only `.notDetermined` permissions, stops after denial, and returns a
fresh `currentState()` result after each request.

In `Package.swift`, add `.linkedFramework("Speech")` to the `RelayVoice`
target's linker settings.

- [ ] **Step 4: Run the readiness tests**

Run:

```bash
swift test --filter RelayVoiceReadinessTests
```

Expected: all readiness tests pass.

- [ ] **Step 5: Commit the readiness service**

```bash
git add Package.swift Sources/RelayVoice/RelayVoiceReadiness.swift Tests/RelayVoiceTests/RelayVoiceReadinessTests.swift
git commit -m "feat: add voice readiness service"
```

---

### Task 2: Preserve Typed Voice Blockers Through Push-to-Talk

**Files:**
- Modify: `Sources/RelayVoice/PushToTalkState.swift`
- Modify: `Sources/RelayVoice/PushToTalkCoordinator.swift`
- Modify: `Sources/RelayVoice/AVAudioEngineMicrophoneCapture.swift`
- Modify: `Tests/RelayVoiceTests/PushToTalkCoordinatorTests.swift`

**Interfaces:**
- Consumes: `RelayVoiceReadinessState` from Task 1 and arbitrary errors thrown by microphone capture or `RelayRealtimeAudioSink`.
- Produces: `RelayVoiceReadinessFailure`, `RelayPushToTalkFailure`, and `PushToTalkState.failed(RelayPushToTalkFailure)`.

- [ ] **Step 1: Write failing typed-failure tests**

Add tests that use this fixture error and assert the readiness state survives:

```swift
private enum ReadinessFixtureError:
    Error,
    RelayVoiceReadinessFailure
{
    case dictationDisabled

    var voiceReadinessState: RelayVoiceReadinessState {
        .dictationDisabled
    }
}

@Test
func startFailurePreservesItsReadinessBlocker() async {
    let coordinator = PushToTalkCoordinator(
        microphone: FakeMicrophoneCapture(),
        sink: RecordingAudioSink(
            startError: ReadinessFixtureError.dictationDisabled
        )
    )

    coordinator.press()
    #expect(await eventually {
        guard case let .failed(failure) = coordinator.state else {
            return false
        }
        return failure.readinessState == .dictationDisabled
            && !failure.message.isEmpty
    })
}
```

Also update the state-machine retry test to construct
`RelayPushToTalkFailure(message: "offline")` instead of passing a bare string.

- [ ] **Step 2: Run the focused tests and verify type mismatches fail**

Run:

```bash
swift test --filter PushToTalkCoordinatorTests
```

Expected: compilation fails because the typed failure interfaces are missing.

- [ ] **Step 3: Implement typed failure propagation**

Add these definitions beside the readiness state:

```swift
public protocol RelayVoiceReadinessFailure: Error {
    var voiceReadinessState: RelayVoiceReadinessState { get }
}

public struct RelayPushToTalkFailure: Equatable, Sendable {
    public let message: String
    public let readinessState: RelayVoiceReadinessState?

    public init(
        message: String,
        readinessState: RelayVoiceReadinessState? = nil
    ) {
        self.message = message
        self.readinessState = readinessState
    }

    public init(error: any Error) {
        let description = (error as NSError).localizedDescription
        message = description.isEmpty ? String(describing: error) : description
        readinessState =
            (error as? any RelayVoiceReadinessFailure)?.voiceReadinessState
    }
}
```

Change `.failed(String)` in both `PushToTalkState` and `PushToTalkEvent` to
`.failed(RelayPushToTalkFailure)`. In `PushToTalkCoordinator`, replace every
`Self.message(for:)` conversion with `RelayPushToTalkFailure(error:)`, while
fixed internal cancellation copy uses `RelayPushToTalkFailure(message:)`.

Conform `RelayMicrophoneCaptureError` to `RelayVoiceReadinessFailure`:

```swift
extension RelayMicrophoneCaptureError: RelayVoiceReadinessFailure {
    public var voiceReadinessState: RelayVoiceReadinessState {
        switch self {
        case .permissionDenied: .microphoneDenied
        case .permissionRestricted: .microphoneRestricted
        case .inputUnavailable: .microphoneUnavailable
        case .alreadyCapturing, .invalidConfiguration, .converterUnavailable:
            .microphoneUnavailable
        }
    }
}
```

- [ ] **Step 4: Run all RelayVoice tests**

Run:

```bash
swift test --filter RelayVoiceTests
```

Expected: all RelayVoice tests pass.

- [ ] **Step 5: Commit typed blocker propagation**

```bash
git add Sources/RelayVoice Tests/RelayVoiceTests
git commit -m "feat: preserve voice readiness failures"
```

---

### Task 3: Classify Apple Speech Failures

**Files:**
- Modify: `Sources/RelayCodexBridge/AppleSpeechTranscriber.swift`
- Create: `Tests/RelayCodexBridgeTests/AppleSpeechTranscriberErrorTests.swift`

**Interfaces:**
- Consumes: Apple Speech callback errors and `RelayVoiceReadinessFailure` from Task 2.
- Produces: `AppleSpeechTranscriberError.dictationDisabled`, `.networkUnavailable`, and `AppleSpeechTranscriberError.classify(_:)`.

- [ ] **Step 1: Write failing classification tests**

```swift
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
                NSLocalizedDescriptionKey: "Siri and Dictation are disabled",
            ]
        )
        let error = AppleSpeechTranscriberError.classify(source)

        #expect(error == .dictationDisabled)
        #expect(error.voiceReadinessState == .dictationDisabled)
    }

    @Test
    func classifiesOfflineRecognition() {
        let source = URLError(.notConnectedToInternet)
        let error = AppleSpeechTranscriberError.classify(source)

        #expect(error == .networkUnavailable)
        #expect(error.voiceReadinessState == .networkUnavailable)
    }

    @Test
    func leavesUnknownErrorsUnclassified() {
        let source = NSError(domain: "Fixture", code: 7)
        #expect(AppleSpeechTranscriberError.classify(source) == nil)
    }
}
```

- [ ] **Step 2: Run the test and verify missing cases fail compilation**

Run:

```bash
swift test --filter AppleSpeechTranscriberErrorTests
```

Expected: compilation fails because the new cases and classifier do not exist.

- [ ] **Step 3: Implement narrow, diagnostic-preserving classification**

Add the two cases and localized descriptions to
`AppleSpeechTranscriberError`, then conform it to
`RelayVoiceReadinessFailure`. Implement:

```swift
public static func classify(
    _ error: any Error
) -> AppleSpeechTranscriberError? {
    let cocoaError = error as NSError
    if cocoaError.localizedDescription.localizedCaseInsensitiveContains(
        "Siri and Dictation are disabled"
    ) {
        return .dictationDisabled
    }
    if let urlError = error as? URLError,
       [
           .notConnectedToInternet,
           .networkConnectionLost,
           .cannotConnectToHost,
           .timedOut,
       ].contains(urlError.code) {
        return .networkUnavailable
    }
    return nil
}
```

At the `resultStream` catch boundary in `finish()`, clean up and throw
`Self.classify(error) ?? error`. This keeps unknown NSError domains, codes, and
descriptions intact.

- [ ] **Step 4: Run bridge and voice tests**

Run:

```bash
swift test --filter AppleSpeechTranscriberErrorTests
swift test --filter RelayCodexBridgeTests
swift test --filter RelayVoiceTests
```

Expected: all three commands pass.

- [ ] **Step 5: Commit Apple Speech classification**

```bash
git add Sources/RelayCodexBridge/AppleSpeechTranscriber.swift Tests/RelayCodexBridgeTests/AppleSpeechTranscriberErrorTests.swift
git commit -m "fix: classify voice setup blockers"
```

---

### Task 4: Gate Voice Attempts in the App Model

**Files:**
- Create: `Sources/RelayApp/Voice/RelayVoiceSetupPresentation.swift`
- Create: `Sources/RelayApp/Voice/RelayVoiceSettingsOpener.swift`
- Modify: `Sources/RelayApp/RelayAppModel.swift`
- Modify: `Tests/RelayAppTests/RelayAppModelTests.swift`
- Create: `Tests/RelayAppTests/RelayVoiceSetupPresentationTests.swift`

**Interfaces:**
- Consumes: `RelayVoiceReadinessChecking`, `RelayVoiceReadinessState`, and `RelayPushToTalkFailure`.
- Produces: `RelayVoiceSetupPresentation`, `RelayVoiceSetupAction`, `RelayVoiceSettingsDestination`, `RelayAppModel.requestVoiceSetupAction()`, and `RelayAppModel.dismissVoiceSetup()`.

- [ ] **Step 1: Write failing presentation and gating tests**

The presentation tests assert exact mappings:

```swift
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
    #expect(presentation.primaryAction == .openSettings(.microphone))
    #expect(presentation.primaryActionTitle == "Open Microphone Settings")
}

@Test
func disabledDictationOffersKeyboardSettings() {
    #expect(
        RelayVoiceSetupPresentation(state: .dictationDisabled).primaryAction
            == .openSettings(.dictation)
    )
}
```

Add AppModel tests using a readiness spy and an injected `startVoice` closure:

```swift
@Test
func firstVoiceAttemptShowsSetupWithoutStartingCapture() async {
    let readiness = VoiceReadinessSpy(state: .needsMicrophoneRequest)
    var startCount = 0
    let model = RelayAppModel(
        commandHandler: CommandHandlerStub(result: .success("unused")),
        voiceReadiness: readiness,
        startVoice: { startCount += 1 }
    )

    await model.beginVoiceAttempt()

    #expect(startCount == 0)
    #expect(model.voiceSetup?.primaryAction == .requestPermissions)
}

@Test
func permissionCompletionRequiresAFreshVoiceAttempt() async {
    let readiness = VoiceReadinessSpy(
        state: .needsMicrophoneRequest,
        requestResult: .ready
    )
    var startCount = 0
    let model = RelayAppModel(
        commandHandler: CommandHandlerStub(result: .success("unused")),
        voiceReadiness: readiness,
        startVoice: { startCount += 1 }
    )

    await model.beginVoiceAttempt()
    await model.requestVoiceSetupAction()
    #expect(startCount == 0)
    #expect(model.voiceSetup?.title == "Voice is ready")

    await model.beginVoiceAttempt()
    #expect(startCount == 1)
    #expect(model.voiceSetup == nil)
}
```

- [ ] **Step 2: Run focused app tests and verify missing interfaces fail**

Run:

```bash
swift test --filter RelayVoiceSetupPresentationTests
swift test --filter RelayAppModelTests
```

Expected: compilation fails because setup presentation and model injection do
not exist.

- [ ] **Step 3: Implement presentation mapping and Settings opening**

Define these exact values:

```swift
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

    init(state: RelayVoiceReadinessState) {
        switch state {
        case .ready:
            self = .ready
        case .needsMicrophoneRequest, .needsSpeechRecognitionRequest:
            self.init(
                title: "Set up voice",
                message: "Relay needs Microphone and Speech Recognition access before Option-Space can listen.",
                primaryAction: .requestPermissions,
                primaryActionTitle: "Continue",
                diagnostic: nil
            )
        case .microphoneDenied:
            self.init(
                title: "Microphone access is off",
                message: "Allow Relay to use the microphone while you hold Option-Space.",
                primaryAction: .openSettings(.microphone),
                primaryActionTitle: "Open Microphone Settings",
                diagnostic: nil
            )
        case .microphoneRestricted:
            self.init(
                title: "Microphone access is restricted",
                message: "Screen Time or device management may prevent Relay from using this Mac’s microphone.",
                primaryAction: .openSettings(.microphone),
                primaryActionTitle: "Open Microphone Settings",
                diagnostic: nil
            )
        case .speechRecognitionDenied:
            self.init(
                title: "Speech Recognition is off",
                message: "Allow Relay to turn your spoken command into text.",
                primaryAction: .openSettings(.speechRecognition),
                primaryActionTitle: "Open Speech Recognition Settings",
                diagnostic: nil
            )
        case .speechRecognitionRestricted:
            self.init(
                title: "Speech Recognition is restricted",
                message: "Screen Time or device management may prevent speech recognition on this Mac.",
                primaryAction: .openSettings(.speechRecognition),
                primaryActionTitle: "Open Speech Recognition Settings",
                diagnostic: nil
            )
        case .dictationDisabled:
            self.init(
                title: "Turn on Dictation",
                message: "Enable Dictation in System Settings → Keyboard, then hold Option-Space again.",
                primaryAction: .openSettings(.dictation),
                primaryActionTitle: "Open Keyboard Settings",
                diagnostic: nil
            )
        case let .unsupportedLocale(locale):
            self.init(
                title: "Language isn’t supported",
                message: "Apple Speech doesn’t support Relay’s current locale: \(locale). Enable a supported Dictation language in Keyboard Settings.",
                primaryAction: .openSettings(.dictation),
                primaryActionTitle: "Open Keyboard Settings",
                diagnostic: nil
            )
        case let .recognizerUnavailable(locale):
            self.init(
                title: "Speech Recognition is unavailable",
                message: "Apple Speech is not currently available for \(locale). Try again later.",
                primaryAction: nil,
                primaryActionTitle: nil,
                diagnostic: nil
            )
        case .microphoneUnavailable:
            self.init(
                title: "No microphone is available",
                message: "Connect or select a microphone, then hold Option-Space again.",
                primaryAction: nil,
                primaryActionTitle: nil,
                diagnostic: nil
            )
        case .networkUnavailable:
            self.init(
                title: "Speech Recognition needs a connection",
                message: "This language cannot currently recognize speech on device. Connect to the internet and try again.",
                primaryAction: nil,
                primaryActionTitle: nil,
                diagnostic: nil
            )
        }
    }

    static let ready = RelayVoiceSetupPresentation(
        title: "Voice is ready",
        message: "Hold Option-Space again to speak to Relay.",
        primaryAction: nil,
        primaryActionTitle: nil,
        diagnostic: nil
    )
}
```

Unknown runtime errors use a separate initializer with title “Voice couldn’t
start,” the localized message, no primary action, and the full diagnostic
string so no text is truncated or discarded.

`RelayVoiceSettingsOpener` maps destinations to these best-effort URLs and then
falls back to `x-apple.systempreferences:`:

```swift
microphone:
    "x-apple.systempreferences:com.apple.preference.security?Privacy_Microphone"
speechRecognition:
    "x-apple.systempreferences:com.apple.preference.security?Privacy_SpeechRecognition"
dictation:
    "x-apple.systempreferences:com.apple.Keyboard-Settings.extension"
```

- [ ] **Step 4: Implement AppModel gating**

Inject `voiceReadiness`, `startVoice`, and a Settings opener while preserving
production defaults. Convert shortcut press handling into an async
`beginVoiceAttempt()`:

```swift
func beginVoiceAttempt() async {
    guard canBeginCommand else { return }
    let readiness = voiceReadiness.currentState()
    guard readiness == .ready else {
        voiceSetup = RelayVoiceSetupPresentation(state: readiness)
        return
    }
    voiceSetup = nil
    latestResponse = nil
    voiceAwaitingAnswer = false
    startVoice()
}
```

`requestVoiceSetupAction()` requests both permissions sequentially when the
action is `.requestPermissions`, publishes `.ready` without starting capture,
or replaces the presentation with the returned blocker. Settings actions open
the selected pane and leave the current voice attempt cancelled.

When push-to-talk publishes `.failed(let failure)`, show a setup presentation
if `failure.readinessState` is non-nil; otherwise show the full runtime failure
presentation and keep the short composer phase free of long error text.

- [ ] **Step 5: Run app model and presentation tests**

Run:

```bash
swift test --filter RelayVoiceSetupPresentationTests
swift test --filter RelayAppModelTests
```

Expected: all focused tests pass, including text submission with denied voice
permissions.

- [ ] **Step 6: Commit app coordination**

```bash
git add Sources/RelayApp/Voice Sources/RelayApp/RelayAppModel.swift Tests/RelayAppTests
git commit -m "feat: gate voice attempts on readiness"
```

---

### Task 5: Render and Visually Verify the Notch Setup Popup

**Files:**
- Create: `Sources/RelayApp/Voice/RelayVoiceSetupView.swift`
- Modify: `Sources/RelayApp/Notch/RelayNotchPanelHost.swift`
- Modify: `Sources/RelayApp/Activity/RelayNotchRootView.swift`
- Modify: `Sources/RelayApp/Composer/RelayCommandComposerView.swift`
- Test: `Tests/RelayAppTests/RelayFinalFixContractsTests.swift`

**Interfaces:**
- Consumes: `RelayVoiceSetupPresentation` and AppModel action methods from Task 4.
- Produces: a fully readable setup overlay and automatic `.expanded` presentation request.

- [ ] **Step 1: Add a failing UI contract test**

Add a source contract test asserting that the setup view is wired into the
root and that the composer no longer receives arbitrary failure copy:

```swift
@Test
func voiceSetupUsesDedicatedExpandedPresentation() throws {
    let root = try source("Sources/RelayApp/Activity/RelayNotchRootView.swift")
    let host = try source("Sources/RelayApp/Notch/RelayNotchPanelHost.swift")

    #expect(root.contains("RelayVoiceSetupView("))
    #expect(host.contains("requestPresentation(.expanded)"))
}
```

- [ ] **Step 2: Run the contract test and verify it fails**

Run:

```bash
swift test --filter RelayFinalFixContractsTests
```

Expected: the new assertions fail because the setup view is not wired.

- [ ] **Step 3: Implement the setup view and host wiring**

Create a focused SwiftUI view with explicit inputs:

```swift
struct RelayVoiceSetupView: View {
    let presentation: RelayVoiceSetupPresentation
    let performPrimaryAction: () -> Void
    let dismiss: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Label(presentation.title, systemImage: "waveform.badge.mic")
                    .font(.headline)
                Spacer()
                Button("Dismiss", systemImage: "xmark", action: dismiss)
                    .labelStyle(.iconOnly)
                    .buttonStyle(.plain)
            }
            Text(presentation.message)
                .foregroundStyle(RelayPalette.secondaryText)
                .fixedSize(horizontal: false, vertical: true)
            if let title = presentation.primaryActionTitle {
                Button(title, action: performPrimaryAction)
                    .buttonStyle(.borderedProminent)
            }
        }
        .padding(20)
        .background(RelayPalette.elevatedSurface, in: .rect(cornerRadius: 18))
        .padding(16)
    }
}
```

Pass `voiceSetup`, primary action, and dismissal through
`RelayNotchPanelHost` into `RelayNotchRootView`. Render the setup view above the
expanded content with a dimming layer, and call
`state.requestPresentation(.expanded)` when setup changes from `nil` to a
value. Keep the rest of the notch interactive only after dismissal.

In `RelayCommandComposerView`, show only `.listening` and `.sending` in the
compact status region. A `.failed` phase must not render a long label; its full
message is owned by the setup/runtime popup.

- [ ] **Step 4: Run focused UI and app tests**

Run:

```bash
swift test --filter RelayFinalFixContractsTests
swift test --filter RelayAppTests
```

Expected: all focused tests pass.

- [ ] **Step 5: Build and launch the changed app**

Run:

```bash
./script/build_and_run.sh --verify
```

Expected: the release build succeeds, one `RelayApp` process launches from
`dist/Relay.app`, and verification reports exactly one process.

- [ ] **Step 6: Exercise and inspect the real popup**

Reset only Relay's development permission decisions on the test Mac, launch
the freshly built app, press Option-Space, and capture the expanded notch after
the Relay explanation appears. Compare it against the existing expanded notch
at the same crop and scale. Verify readable title/body copy, no clipped text,
clear primary/dismiss actions, correct margins, and no overlap with the notch
safe area. Repeat with a denied permission state and the Dictation-disabled
state before claiming visual completion.

- [ ] **Step 7: Run the complete suite and inspect the final diff**

Run:

```bash
swift test
git diff --check
git status --short
```

Expected: the full suite passes, `git diff --check` prints nothing, and status
contains only intentional task files.

- [ ] **Step 8: Commit the UI and verification changes**

```bash
git add Sources/RelayApp Tests/RelayAppTests
git commit -m "feat: show demand-driven voice setup popup"
```
