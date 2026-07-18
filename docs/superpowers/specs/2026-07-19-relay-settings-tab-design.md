# Relay Settings Tab

## Outcome

Relay gives people direct control over the user-facing defaults it currently
chooses for them. Settings live inside the expanded notch panel as a peer of
Chat and Usage, apply immediately, persist across launches, and remain usable
without relying on Relay having a conventional macOS application menu.

The release also closes the update-discoverability gap by putting update
status and a manual **Check Now** action inside Relay itself.

## Information architecture

The expanded section picker gains a third `Settings` destination after Chat
and Usage. Selecting it replaces the section body with a vertically scrolling
settings view that uses Relay's existing density, typography, surfaces, and
focus behavior. It does not open a separate window or add a Dock or menu-bar
item.

The view contains four groups:

1. **Behavior** — launch visibility, automatic activity peeks, and pointer
   display following.
2. **Voice & shortcut** — spoken voice responses, speech voice, and the global
   push-to-talk shortcut.
3. **Updates** — automatic checking, check cadence, installed version, and a
   manual check action.
4. **Usage** — automatic use of expiring reset credits.

A **Restore Defaults** action appears at the bottom. It requires confirmation
because it can change several live behaviors at once. Individual settings do
not have Apply or Save buttons.

## Preferences and defaults

The settings store registers explicit defaults rather than treating a missing
boolean as an accidental product decision. Existing persisted values take
precedence during migration.

| Preference | Initial default | Application timing |
| --- | --- | --- |
| Show compact Relay at launch | On | Next launch |
| Show automatic activity peeks | On | Immediate |
| Follow the pointer across displays | On | Immediate |
| Speak answers to voice commands | On | Immediate; active speech stops when disabled |
| Speech voice | macOS system voice | Next spoken answer |
| Push-to-talk shortcut | Option–Space | Immediate after successful registration |
| Automatically check for updates | On | Immediate |
| Update cadence | Daily | Immediate scheduler reset |
| Apply reset credits before expiry | Off unless already persisted | Immediate |

Update cadence offers Daily and Weekly in the first release. Turning automatic
checks off disables the cadence control but leaves **Check Now** available.

The speech voice picker offers **System Voice** first, followed by installed
voices suitable for the current locale. A stored voice that is no longer
installed falls back to System Voice and is presented that way in Settings.

The shortcut editor records one non-modifier key plus at least one modifier.
Escape cancels recording, Delete restores Option–Space, and a successful
selection replaces the active shortcut immediately.

## Architecture

`RelaySettingsStore` is a main-actor observable object and the sole typed
interface to Relay preferences. It owns persistence keys, registered defaults,
validation, restoration, and value migration. The application delegate creates
one store before constructing the runtime, model, and panel controller, then
passes that same instance to each consumer that needs live settings.

Settings values remain simple data. Side effects stay with the subsystem that
already owns the affected behavior:

- `RelayNotchPanelController` observes launch, peek, and display-following
  preferences. Disabling display following cancels any pending dwell and pins
  Relay to its current display. Disabling automatic peeks dismisses an active
  automatic peek without collapsing a deliberately expanded panel.
- `RelayAppRuntime` registers the configured shortcut and changes it through a
  transactional re-registration method. It also provides speech configuration
  to the synthesizer and voice command sink.
- `RelayUpdateController` synchronizes Sparkle's automatic-check flag and
  scheduled interval, resets Sparkle's cycle when either changes, and exposes
  installed version and manual-check state to the Settings view.
- `RelayActivityStore` uses the shared setting for reset-credit automation
  instead of owning a second persistence key. The existing Usage control and
  the Settings control bind to the same value.

The store does not directly manipulate AppKit, Sparkle, Carbon, speech, or
monitoring objects. This keeps preference persistence testable and prevents
the Settings view from becoming a service coordinator.

## Immediate application and errors

Most controls mutate the settings store directly. Consumers observe changes
and perform their narrow side effect. Launch visibility is labeled as taking
effect the next time Relay opens.

Shortcut changes are transactional: Relay attempts to register the candidate
first. If registration fails because the combination is unavailable or the
system rejects it, the prior shortcut remains registered and persisted. The
Settings row shows an inline error and keeps the previous value. A later
successful edit clears the error.

Disabling spoken responses immediately stops any current utterance and prevents
future voice-command answers from being spoken; it does not disable microphone
input. An unavailable saved speech voice falls back without blocking voice
input or showing a persistent error.

Update check failures use the existing update presentation and retry behavior.
The Settings view reflects checking, available, up-to-date, and failed states,
while installation remains in the existing expanded-panel update banner.

Restoring defaults applies the same validation and side-effect paths as normal
edits. If restoring Option–Space fails to register, the working shortcut is
retained and the restore operation reports that one setting could not be
restored rather than leaving push-to-talk unregistered.

## Accessibility and interaction

Every control has a visible label and concise explanatory copy. Toggle labels
remain available to VoiceOver even when a compact switch is visually separated
from its text. The section picker announces Settings as selected. Shortcut
recording announces when capture starts, succeeds, is cancelled, or fails.

Settings preserve keyboard navigation and do not make hover or pointer input
mandatory. Controls use native SwiftUI toggles, pickers, and buttons where
possible. The shortcut recorder is the only custom interaction and exposes a
standard button entry point plus an accessible textual value.

## Verification

Focused tests cover:

- explicit defaults and migration of the existing reset-credit key;
- persistence and restore-default behavior;
- Settings as a third expanded section and its accessibility label;
- immediate peek and pointer-following policy changes;
- speech enablement and unavailable-voice fallback;
- successful shortcut replacement, failed replacement rollback, cancellation,
  and reset to Option–Space;
- Sparkle automatic-check enablement and Daily/Weekly interval mapping;
- synchronization of reset-credit automation between Usage and Settings; and
- manual update-check presentation from Settings.

The full test suite and release build run after focused checks. Runtime QA opens
the built app, exercises every control, relaunches to confirm persistence and
launch visibility, verifies a real manual update check against the signed feed,
and captures the expanded Settings tab for visual inspection against Relay's
existing Chat and Usage layout.

## Out of scope

This release does not expose controller prompts, model selection, Codex paths,
notch geometry, animation timing, reset-credit lead time, or other engineering
and safety invariants. It does not add a standalone Settings window, Dock icon,
or status item. Additional update cadences, shortcut profiles, and separate
speech rate or volume controls can be considered after observing real use.
