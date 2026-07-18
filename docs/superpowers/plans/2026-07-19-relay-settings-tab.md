# Relay Settings Tab Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (- [ ]) syntax for tracking.

**Goal:** Add an immediately applied, persisted Settings tab inside Relay's expanded notch panel, including a discoverable manual update check.

**Architecture:** A main-actor observable RelaySettingsStore owns typed preferences and persistence. The application delegate injects one store into the model, runtime, panel controller, updater, and views; each subsystem owns its side effects, while Settings and Usage bind to the same values.

**Tech Stack:** Swift 6.2, SwiftUI, Observation, AppKit, Carbon global hot keys, AVFoundation speech synthesis, Sparkle 2, Swift Testing.

## Global Constraints

- Target macOS 15 or later and add no third-party dependency.
- Settings are a third in-panel destination beside Activity, Chat, and Usage; do not add a Dock icon, status item, or standalone window.
- Preserve current behavior as explicit defaults: compact at launch, automatic peeks on, pointer following on, spoken voice answers on, Option-Space, daily automatic update checks, and reset-credit automation off unless already persisted.
- Changes apply immediately except launch visibility, which applies at the next launch.
- A failed shortcut replacement must leave the previous shortcut registered and persisted.
- Manual update checking remains available when automatic checks are disabled.
- Use the existing Relay palette, density, update banner, and reset-credit semantics.

---

### Task 1: Typed persisted settings

**Files:**
- Create: Sources/RelayApp/Settings/RelaySettingsStore.swift
- Test: Tests/RelayAppTests/RelaySettingsStoreTests.swift

**Interfaces:**
- Produces: RelayUpdateCadence, RelaySettingsChange, and @MainActor @Observable final class RelaySettingsStore.
- Produces: mutable user preference properties, onChange, and restoreDefaults().

- [ ] **Step 1: Write failing store tests**

~~~swift
@Test @MainActor
func settingsRegisterExplicitDefaultsAndPersistChanges() {
    let defaults = ephemeralDefaults()
    let settings = RelaySettingsStore(defaults: defaults)
    #expect(settings.showAtLaunch)
    #expect(settings.automaticPeeks)
    #expect(settings.followsPointerAcrossDisplays)
    #expect(settings.speaksVoiceResponses)
    #expect(settings.shortcut == .optionSpace)
    #expect(settings.automaticallyChecksForUpdates)
    #expect(settings.updateCadence == .daily)
    #expect(!settings.autoApplyResetCredits)
    settings.automaticPeeks = false
    #expect(!RelaySettingsStore(defaults: defaults).automaticPeeks)
}
~~~

- [ ] **Step 2: Run the store tests and verify they fail**

Run: swift test --filter RelaySettingsStoreTests

Expected: compilation fails because RelaySettingsStore is not defined.

- [ ] **Step 3: Implement the typed store**

Use keys prefixed with relay.settings. except reuse
relay.autoApplyResetCreditBeforeExpiry. Encode shortcuts with Codable, remove
the speech voice key for the system voice, and call onChange from each didSet
only when the value changed.

~~~swift
enum RelayUpdateCadence: String, CaseIterable, Identifiable, Codable {
    case daily
    case weekly
    var id: Self { self }
    var interval: TimeInterval { self == .daily ? 86_400 : 604_800 }
}

enum RelaySettingsChange: Equatable {
    case showAtLaunch(Bool)
    case automaticPeeks(Bool)
    case followsPointerAcrossDisplays(Bool)
    case speaksVoiceResponses(Bool)
    case speechVoiceIdentifier(String?)
    case shortcut(RelayGlobalShortcut)
    case automaticallyChecksForUpdates(Bool)
    case updateCadence(RelayUpdateCadence)
    case autoApplyResetCredits(Bool)
    case restoredDefaults
}
~~~

- [ ] **Step 4: Run store tests**

Run: swift test --filter RelaySettingsStoreTests

Expected: all store tests pass.

- [ ] **Step 5: Commit the settings store**

~~~bash
git add Sources/RelayApp/Settings/RelaySettingsStore.swift Tests/RelayAppTests/RelaySettingsStoreTests.swift
git commit -m "feat: add persisted Relay settings"
~~~

### Task 2: Transactional shortcut and live speech configuration

**Files:**
- Modify: Sources/RelayCodexBridge/AppleSpeechSynthesizer.swift
- Modify: Sources/RelayCodexBridge/AppleSpeechCommandSink.swift
- Modify: Sources/RelayApp/RelayAppRuntime.swift
- Modify: Sources/RelayApp/RelayAppModel.swift
- Test: Tests/RelayCodexBridgeTests/AppleSpeechCommandSinkTests.swift
- Test: Tests/RelayAppTests/RelayAppModelTests.swift

**Interfaces:**
- Consumes: RelaySettingsStore and RelaySettingsChange.
- Produces: AppleSpeechSynthesizer.configure(enabled:voiceIdentifier:).
- Produces: RelayAppRuntime.applySettingsChange(_:shortcutHandler:) and RelayAppModel.applySettingsChange(_:).

- [ ] **Step 1: Add failing speech and shortcut rollback tests**

~~~swift
@Test
func disabledSpeechDoesNotSpeakTheCompletedAnswer() async throws {
    let synthesizer = SpeechSynthesizerSpy()
    let sink = AppleSpeechCommandSink(
        transcriber: SpeechTranscriberSpy(result: "Status"),
        commandHandler: CommandHandlerSpy(answer: "Complete"),
        synthesizer: synthesizer,
        shouldSpeakResponses: { false }
    )
    try await sink.start()
    try await sink.finishAndSend()
    #expect(await synthesizer.spokenTexts.isEmpty)
}
~~~

Add a runtime shortcut-monitor spy whose candidate monitor throws from start;
assert the original monitor is not stopped and the setting rolls back.

- [ ] **Step 2: Run focused tests and verify failure**

Run: swift test --filter AppleSpeechCommandSinkTests

Expected: compilation fails because shouldSpeakResponses is unavailable.

- [ ] **Step 3: Implement live speech and transactional shortcut replacement**

Add a sendable async shouldSpeakResponses closure to the voice sink and guard it
before speaking. Make the concrete synthesizer's enabled flag and voice
identifier mutable and stop current speech when disabling.

In RelayAppRuntime, retain the shortcut handler and a monitor factory. Start a
candidate monitor before stopping the old monitor, and only swap after success.
Read initial shortcut and speech values from the injected store.

In RelayAppModel, forward relevant changes to a started runtime and roll the
stored shortcut back without re-entering replacement when registration fails.

- [ ] **Step 4: Run focused voice and model tests**

Run: swift test --filter AppleSpeechCommandSinkTests && swift test --filter RelayAppModelTests

Expected: both suites pass.

- [ ] **Step 5: Commit runtime settings behavior**

~~~bash
git add Sources/RelayCodexBridge Sources/RelayApp/RelayAppRuntime.swift Sources/RelayApp/RelayAppModel.swift Tests/RelayCodexBridgeTests Tests/RelayAppTests/RelayAppModelTests.swift
git commit -m "feat: apply voice and shortcut settings live"
~~~

### Task 3: Live panel, launch, usage, and updater settings

**Files:**
- Modify: Sources/RelayApp/RelayApplicationDelegate.swift
- Modify: Sources/RelayApp/Notch/RelayNotchPanelController.swift
- Modify: Sources/RelayApp/Notch/RelayNotchPanelHost.swift
- Modify: Sources/RelayApp/Activity/RelayNotchRootView.swift
- Modify: Sources/RelayApp/Monitoring/RelayActivityStore.swift
- Modify: Sources/RelayApp/Updates/RelayUpdateController.swift
- Test: Tests/RelayAppTests/RelayPanelPresentationTests.swift
- Test: Tests/RelayAppTests/RelayActivityStoreTests.swift
- Test: Tests/RelayAppTests/RelayUpdateConfigurationTests.swift

**Interfaces:**
- Produces: RelayNotchPanelController.applySettingsChange(_:).
- Produces: RelayUpdateController.configure(settings:), installedVersion, and cadence synchronization.
- Produces: RelayAutomaticPeekPolicy.trigger(_:enabled:).

- [ ] **Step 1: Add failing subsystem tests**

~~~swift
@Test @MainActor
func weeklyUpdateCadenceMapsToSevenDays() {
    #expect(RelayUpdateCadence.weekly.interval == 604_800)
}

@Test @MainActor
func settingsCanSuppressAutomaticPeekTrigger() {
    #expect(RelayAutomaticPeekPolicy.trigger(candidate, enabled: false) == nil)
    #expect(RelayAutomaticPeekPolicy.trigger(candidate, enabled: true) == candidate)
}
~~~

Extend activity-store tests with a shared settings store and assert reset-credit
automation follows that single value.

- [ ] **Step 2: Run focused tests and verify failure**

Run: swift test --filter RelayPanelPresentationTests && swift test --filter RelayUpdateConfigurationTests && swift test --filter RelayActivityStoreTests

Expected: compilation fails because the policy and configuration seams do not exist.

- [ ] **Step 3: Wire settings to subsystem owners**

The delegate constructs one store, configures the updater, creates the model and
panel controller with it, installs one change dispatcher, and only presents
compact Relay at launch when showAtLaunch is true.

The panel controller guards pointer observation and relocation with the setting;
disabling it cancels pending relocation. The root view filters automatic peek
triggers through the policy. The activity store binds its existing automation
to the shared store. The updater maps automatic checking and cadence to Sparkle
and resets its update cycle.

- [ ] **Step 4: Run focused subsystem tests**

Run: swift test --filter RelayPanelPresentationTests && swift test --filter RelayUpdateConfigurationTests && swift test --filter RelayActivityStoreTests

Expected: all selected suites pass.

- [ ] **Step 5: Commit subsystem wiring**

~~~bash
git add Sources/RelayApp Tests/RelayAppTests
git commit -m "feat: apply panel and update preferences"
~~~

### Task 4: Settings tab and controls

**Files:**
- Create: Sources/RelayApp/Settings/RelaySettingsView.swift
- Create: Sources/RelayApp/Settings/RelayShortcutRecorder.swift
- Create: Sources/RelayApp/Settings/RelaySpeechVoiceOption.swift
- Modify: Sources/RelayApp/Composer/RelayExpandedSection.swift
- Modify: Sources/RelayApp/Composer/RelayExpandedSectionPicker.swift
- Modify: Sources/RelayApp/Activity/RelayExpandedActivityView.swift
- Modify: Sources/RelayApp/Activity/RelayNotchRootView.swift
- Modify: Sources/RelayApp/Notch/RelayNotchPanelHost.swift
- Test: Tests/RelayAppTests/RelaySettingsPresentationTests.swift

**Interfaces:**
- Produces: RelaySettingsView(settings:updateController:shortcutError:).
- Produces: RelayShortcutRecorder(shortcut:onCommit:) with Escape cancel and Delete restore.

- [ ] **Step 1: Add failing presentation tests**

~~~swift
@Test
func expandedSectionsIncludeSettingsAfterUsage() {
    #expect(RelayExpandedSection.allCases == [.activity, .chat, .usage, .settings])
}

@Test
func shortcutCopyUsesMacModifierGlyphs() {
    #expect(RelayShortcutPresentation.copy(for: .optionSpace) == "⌥Space")
}
~~~

- [ ] **Step 2: Run presentation tests and verify failure**

Run: swift test --filter RelaySettingsPresentationTests

Expected: compilation fails because the Settings types are not defined.

- [ ] **Step 3: Implement the Settings destination and controls**

Add .settings = "Settings", resize the segmented picker for four labels, add the
Settings switch case, and pass the shared store through host/root/expanded
views.

Build one scrolling view with Behavior, Voice & Shortcut, Updates, and Usage
groups. Use native switches and menus, installed version copy, a Check Now
button that remains enabled when automatic checks are off, inline shortcut
errors, and a two-click Restore Defaults confirmation.

Implement shortcut capture with a focusable NSViewRepresentable that requires a
modifier plus non-modifier key, maps Escape to cancel, and maps Delete to
Option-Space. Expose state and result copy to accessibility.

- [ ] **Step 4: Run presentation and panel tests**

Run: swift test --filter RelaySettingsPresentationTests && swift test --filter RelayPanelPresentationTests

Expected: all selected tests pass.

- [ ] **Step 5: Commit the Settings UI**

~~~bash
git add Sources/RelayApp Tests/RelayAppTests
git commit -m "feat: add in-panel Settings tab"
~~~

### Task 5: Integration verification and visual QA

**Files:**
- Modify if necessary: files from Tasks 1–4 only.
- Verify: dist/Relay.app

- [ ] **Step 1: Run the complete test suite**

Run: git diff --check && swift test

Expected: no whitespace errors and zero failures.

- [ ] **Step 2: Build the release executable**

Run: swift build -c release

Expected: successful release compilation.

- [ ] **Step 3: Build and launch the local app**

Run scripts/build-local-app.sh, terminate the previously running local Relay
process, and open dist/Relay.app.

Expected: the bundle passes codesign verification and launches.

- [ ] **Step 4: Inspect every Settings group in the running app**

Expand Relay, select Settings, capture the panel, and compare hierarchy,
density, typography, spacing, colors, controls, and visual weight with Chat and
Usage. Exercise every control, confirm Check Now reaches the signed feed,
confirm shortcut rollback, and relaunch to confirm persistence and launch
visibility.

- [ ] **Step 5: Re-run verification after visual corrections**

Run: git diff --check && swift test && swift build -c release

Expected: all commands pass after the latest visually inspected version.

- [ ] **Step 6: Commit final integration corrections if any**

~~~bash
git add Sources Tests
git commit -m "fix: polish Relay settings integration"
~~~

