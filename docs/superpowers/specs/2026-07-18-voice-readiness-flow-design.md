# Relay Voice Readiness Flow

## Goal

Make voice setup demand-driven and actionable. Relay should remain immediately
usable for task monitoring and text commands, while the first attempt to use
Option-Space guides the user through every prerequisite needed for voice.

The original shortcut press must never continue into recording after Relay
shows a permission prompt or sends the user to System Settings. Once setup is
ready, Relay tells the user to hold Option-Space again.

## Requirements

Relay voice depends on these conditions:

- Relay has macOS Microphone permission.
- Relay has macOS Speech Recognition permission.
- macOS Dictation is enabled.
- Apple Speech supports the current locale and its recognizer is available.
- A usable microphone input is available.
- Network access is available when the selected recognizer cannot operate on
  device.

Accessibility permission is not a voice requirement. Relay should continue to
request it only when a user invokes the Codex Desktop follow-up path that types
and submits text through synthetic keyboard events.

The global Option-Space shortcut uses Carbon hot-key registration and does not
require Accessibility or Input Monitoring permission. Shortcut registration
failures remain a separate startup concern.

## Interaction Model

Voice setup is triggered only by an attempted voice interaction. Relay does not
show a setup wizard at ordinary launch and does not block text or task features.

On Option-Space press:

1. `RelayAppModel` asks a voice readiness service whether recording can begin.
2. If both app permissions are already granted and the recognizer is available,
   Relay begins the existing push-to-talk path.
3. If a permission is undetermined, Relay presents a compact explanation before
   invoking the native macOS prompt.
4. Permission requests run sequentially: Microphone first, then Speech
   Recognition. Relay never stacks system prompts.
5. Showing a permission prompt consumes the current voice attempt. After the
   result, Relay displays either the next required action or “Voice is ready —
   hold Option-Space again.”
6. If a permission is denied or restricted, Relay shows the relevant blocker
   and a button that opens its System Settings destination.
7. If Apple Speech reports that Siri and Dictation are disabled, Relay maps the
   system error to an actionable Dictation blocker with an **Open Keyboard
   Settings** button.

macOS does not provide a reliable public API for reading the Dictation toggle.
Relay must not read private preference domains. It should learn that Dictation
is disabled from the Apple Speech task failure and preserve that blocker until
the next readiness attempt verifies that recognition can start.

## Architecture

### Voice readiness service

Add a focused `RelayVoiceReadinessService` boundary. It owns platform checks,
permission requests, recognizer preflight, and Settings destinations. It does
not own microphone capture, transcription sessions, shortcut registration, or
UI presentation.

The service exposes a `RelayVoiceReadinessState` value suitable for
deterministic testing, with these cases:

- `ready`
- `needsMicrophoneRequest`
- `needsSpeechRecognitionRequest`
- `microphoneDenied`
- `microphoneRestricted`
- `speechRecognitionDenied`
- `speechRecognitionRestricted`
- `dictationDisabled`
- `unsupportedLocale`
- `recognizerUnavailable`
- `microphoneUnavailable`
- `networkUnavailable`

These states remain explicit rather than collapsing into arbitrary localized
error strings.

Permission request APIs remain behind injected closures or a protocol so tests
do not trigger macOS prompts. Production uses `AVAudioApplication` or
`AVCaptureDevice` for Microphone authorization and `SFSpeechRecognizer` for
Speech Recognition authorization.

### App model coordination

`RelayAppModel` remains the coordinator for shortcut events and composer phase.
Before calling `PushToTalkCoordinator.press()`, it consults the readiness
service. A ready result proceeds immediately. Any other result updates a
dedicated voice setup presentation and does not start microphone capture.

Permission request results return to the main actor and update that
presentation. They do not synthesize a new shortcut event or automatically
start recording.

### Speech error classification

`AppleSpeechTranscriber` or a small adjacent classifier converts known Apple
Speech failures into typed Relay failures. In particular, the underlying “Siri
and Dictation are disabled” failure becomes `dictationDisabled`. Unknown Apple
errors retain their underlying domain, code, and localized description for
diagnostics, while the user-facing presentation remains readable.

Error classification should prefer stable error domains and codes where Apple
provides them. A narrowly scoped message match may be retained as a fallback for
the Dictation-disabled error because Apple does not expose the toggle through a
public readiness API.

## Presentation

Actionable voice setup failures live in a dedicated Relay popup rendered in the
existing notch-panel visual language. When voice needs attention, Relay expands
the panel automatically so the message cannot be hidden in the compact composer.

Each state shows:

- a short title;
- one concise explanation;
- one primary action when the user can resolve the issue;
- a dismiss action that leaves text and task features usable.

Settings actions are specific:

- **Open Microphone Settings**
- **Open Speech Recognition Settings**
- **Open Keyboard Settings** for Dictation

Where a version-specific Settings deep link is unavailable or rejected, Relay
falls back to opening System Settings and gives the exact navigation path in
the popup.

Short transient states such as Listening and Sending may remain in the composer
status label. The existing one-line, fixed-width status region must not display
long setup errors. Unknown runtime failures should also have an expandable or
otherwise fully readable presentation rather than being silently truncated.

## Error Behavior

- Denied permission: explain that macOS will not show the native prompt again
  and provide the corresponding Settings action.
- Restricted permission: explain that Screen Time or device management may be
  responsible; do not imply the user can always change it.
- Dictation disabled: direct the user to System Settings → Keyboard → Dictation.
- Unsupported locale: name the current locale and direct the user to enable a
  supported Dictation language.
- Recognizer unavailable: identify the service as temporarily unavailable and
  invite a later retry.
- Missing microphone: ask the user to connect or select a microphone.
- Network-dependent recognition: state that the selected language requires a
  connection when on-device recognition is unavailable.
- Unknown error: show a concise summary plus a way to reveal or copy the full
  diagnostic description.

Opening Settings or dismissing the popup cancels the current voice attempt.
Returning from Settings does not claim success from stale state. Relay checks
readiness again on the next Option-Space press.

## Persistence

Relay does not need a “completed onboarding” flag. Current platform state is the
source of truth because users and administrators can revoke permissions or
change Dictation settings later.

Relay may remember the most recently classified Dictation blocker for the
current process so it can present useful guidance immediately. It must recheck
on the next voice attempt and clear the blocker once Apple Speech starts
successfully.

## Testing

Unit tests cover:

- every readiness state and its user-facing action;
- sequential Microphone and Speech Recognition requests;
- no request when authorization is already granted or denied;
- cancellation of the original shortcut attempt whenever setup UI or a native
  prompt appears;
- a successful fresh Option-Space attempt after readiness becomes `ready`;
- Settings destination selection and fallback behavior;
- classification of the Dictation-disabled Apple Speech failure;
- supported and unsupported current locales;
- recognizer and microphone unavailability;
- preservation of the underlying diagnostic data for unknown errors;
- text submission and task monitoring remaining usable with all voice
  permissions denied.

Integration tests verify that `RelayAppModel` never invokes microphone capture
for a non-ready result and invokes it exactly once for a ready result.

Manual verification on a clean macOS user account covers the real native prompt
sequence, denial and later Settings recovery, Dictation disabled and enabled,
the fully readable popup at the notch, and a successful press-hold-release voice
command after setup.

## Non-Goals

- A launch-blocking onboarding wizard.
- Automatically enabling macOS Dictation or Accessibility.
- Reading private macOS preference domains.
- Requesting Accessibility as part of voice setup.
- Automatically recording after a permission dialog closes.
- Replacing the existing push-to-talk coordinator or transcription pipeline.
