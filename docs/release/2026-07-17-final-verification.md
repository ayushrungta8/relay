# Relay Final Cross-Layer Verification

Status: **DONE**

## Outcome

Implemented every Critical, Important, and Minor item in
`final-review-findings.md` without weakening the accepted controller/worker
request-ownership boundary or exact-path process safety:

- Controller agent-message deltas now flow through the session, event
  processor, command handler, typed composer, and push-to-talk path. Expanded
  Relay shows the progressively updated answer in an accessible, selectable
  surface.
- A dedicated presentation coordinator observes new highest-priority
  attention, presents a nonactivating peek, and cancels/dismisses it after four
  seconds. Menu and Shift-Command-R global invocation both use pointer-screen
  `toggle`; Option-Space keeps a distinct Carbon hot-key identity.
- Expanded mode shows honest reconnecting/offline freshness, last-snapshot
  age, the connection error, and Retry.
- Pending-answer and follow-up drafts live in persistent panel state. Dirty
  drafts block Escape/outside-click collapse or dismissal until their explicit
  Cancel controls discard them.
- Overlapping refreshes coalesce into an immediate rerun. Events received
  during a suspended snapshot are versioned and replayed before publication;
  unknown-thread status events request a coalesced read.
- Latest turn status/error are retained. A terminal failed turn derives failed
  attention and its terminal error outranks earlier progress items.
- Compact/expanded card activation and keyboard focus select the task. Current
  selection clears when its task disappears while last interaction remains.
- Successful owned submissions remain visibly resolving and cannot be
  resubmitted until authoritative status clears the waiting flags. A short
  model-side retention closes the broker/store publication race without ever
  fabricating external ownership.
- Selected question choices show a checkmark/tint and VoiceOver `.isSelected`;
  answer fields include their question headers.
- Removed the duplicate startup refresh.
- Exact-path termination and verification polling now perform a final
  timeout-edge scan.

## Files

Production changes:

- `Sources/RelayBrain/RelayControllerSession.swift`
- `Sources/RelayCodexBridge/{CodexControllerSessionAdapter,RelayControllerEventProcessor,RelayControllerRuntime,AppleSpeechCommandSink,RelayVoiceControllerEvent,RelayPendingInteractionBroker}.swift`
- `Sources/RelayCodexClient/{CodexMonitoringClient,CodexMonitoringModels}.swift`
- `Sources/RelayCore/{RelayTaskActivity,RelayPendingInteraction}.swift`
- `Sources/RelayVoice/{RelayGlobalShortcut,CarbonGlobalShortcutMonitor}.swift`
- `Sources/RelayApp/RelayAppModel.swift`
- `Sources/RelayApp/RelayApplication.swift`
- `Sources/RelayApp/Activity/*.swift` for answer, draft, selection, resolving,
  and selected-option presentation
- `Sources/RelayApp/Composer/RelayControllerAnswerView.swift`
- `Sources/RelayApp/Monitoring/*.swift` for freshness, coalescing, event replay,
  selection, and status normalization
- `Sources/RelayApp/Notch/*.swift` for draft state, automatic peek
  coordination, global toggle, and dismissal guards
- `script/relay_process_helpers.sh`
- `script/build_and_run_process_test.sh`

Test changes:

- `Tests/RelayAppTests/{RelayFinalFixContractsTests,RelayActivityStoreTests,RelayActivityReducerTests,RelayAppModelTests}.swift`
- `Tests/RelayCodexBridgeTests/{CodexControllerSessionAdapterTests,RelayControllerRuntimeTests,AppleSpeechCommandSinkTests,RelayPendingInteractionBrokerTests}.swift`
- `Tests/RelayCodexClientTests/CodexMonitoringClientTests.swift`
- `Tests/RelayCoreTests/RelayTaskActivityTests.swift`

## TDD Evidence

Initial focused RED command:

```text
swift test --filter 'RelayFinalFixContractsTests|RelayTaskActivityTests|CodexControllerSessionAdapterTests|RelayControllerRuntimeTests|CodexMonitoringClientTests|RelayActivityReducerTests|RelayActivityStoreTests|RelayPendingInteractionBrokerTests'
```

Exited `1` on the intended missing contracts, including:

```text
extra trailing closure passed in call
type 'RelayControllerEvent' has no member 'textDelta'
extra arguments at positions #3, #4 in call
```

The process RED command:

```text
./script/build_and_run_process_test.sh
```

Exited `1` at the synthetic timeout edge:

```text
error: expected one process for /final-scan/RelayApp, found none
```

Focused GREEN evidence:

- Cross-layer suite: `52 tests in 8 suites passed`.
- Typed/voice/adapter suite: `27 tests in 5 suites passed`.
- Post-self-review core suite: `31 tests in 4 suites passed`.
- Process test: `exact-path process matching passed`.

## Final Test and Build Evidence

Fresh final commands:

```text
swift test
swift build -c release
./script/build_and_run_process_test.sh
bash -n script/build_and_run.sh
bash -n script/build_and_run_process_test.sh
bash -n script/relay_process_helpers.sh
git diff --check
```

Results:

```text
Test run with 164 tests in 36 suites passed after 1.611 seconds.
Build complete! (11.53s)
exact-path process matching passed
```

All syntax and whitespace checks exited `0`.

## Launch and Process Evidence

Command:

```text
./script/build_and_run.sh --verify
```

Exited `0`, rebuilt and signed the exact staged bundle, verified its designated
requirement, and launched PID `99300`:

```text
/Users/ayushrungta/Work/Relay/dist/Relay.app
99300
```

Final process inspection:

```text
exact_app_count=1
app_pid=99300
direct_app_server_count=1
```

The only direct app-server child is PID `99359`:

```text
/Applications/ChatGPT.app/Contents/Resources/codex app-server --stdio
```

The exact staged app was intentionally left running.

## Commit

```text
4d79d08cbaedece46a6bbacc00e7d201ece2c50a
fix: complete Relay cross-layer review wave
```

## Self-Review

- Controller automatic responses remain limited to the live hidden-controller
  identity; worker requests remain broker-owned only when observed on Relay's
  connection.
- Resolving records retain their generation/token protections, and replacement
  records cannot be removed or restored by suspended old submissions.
- The streamed overload is a protocol requirement, not extension-only static
  dispatch, so existential command handlers receive progressive updates.
- Panel and push-to-talk Carbon monitors use distinct IDs, preventing either
  shortcut handler from accepting the other's hot-key event.
- Snapshot replay is actor-isolated; UI publication remains MainActor-isolated.
- New SwiftUI state lives in focused types/files, uses semantic text, visible
  non-color selection cues, keyboard focus selection, and VoiceOver traits.
- Process helpers continue matching the complete executable path and never use
  basename-wide termination.

## Concerns

No blocking concerns. Deterministic geometry, accessibility, shortcut, and
process contracts are covered; a physical multi-display/VoiceOver pass remains
useful release QA but is not required to satisfy this fix contract.

## Final Re-review Residual Wave

Status: **DONE**

Implemented every item in `final-rereview-findings.md`:

- Retry now cancels delayed reconnect backoff and immediately reconnects before
  refreshing, recovering a failed persistent transport instead of submitting a
  snapshot request to the failed client.
- Automatic peek identity resets when priority attention clears, so an equal
  same-thread handoff peeks again after a running interval.
- Resolving ownership is retained only through the original authoritative
  waiting state. Store publications permanently prune it once that state
  clears, including absent tasks after a successful snapshot, preventing later
  external waiting from resurrecting ownership and bounding retained memory.
- Menu/global toggle and every direct hidden transition honor the dirty-draft
  guard. Draft keys reconcile against visible tasks and interactions; dirty
  orphan drafts remain in an accessible expanded-panel surface with explicit
  Cancel controls, while clean orphan state is pruned.
- Task operations decode future turn-status strings losslessly while continuing
  to detect known `inProgress` turns for read, steer, and interrupt behavior.

### Residual TDD Evidence

The first focused RED build exited `1` on the intentionally absent contracts:

```text
RelayActivityStore has no member 'retryConnection'
RelayNotchPanelState has no member 'toggleTarget'
RelayPanelDraftStore has no member 'reconcile'
extra argument 'activityStore' in call
```

After those four contracts were GREEN, the isolated task-operations RED test
failed at the intended decoding boundary:

```text
DecodingError.dataCorrupted
thread.turns[0].status
Cannot initialize TurnStatus from invalid String value pausedForReview
```

Final focused command:

```text
swift test --filter 'RelayActivityStoreTests|RelayFinalFixContractsTests|RelayAppModelTests|CodexTaskOperationsClientTests'
```

Result: `35 tests in 4 suites passed`.

### Residual Full Verification

Fresh commands:

```text
swift test
swift build -c release
./script/build_and_run_process_test.sh
bash -n script/build_and_run.sh
bash -n script/build_and_run_process_test.sh
bash -n script/relay_process_helpers.sh
git diff --check
./script/build_and_run.sh --verify
```

Results:

```text
Test run with 170 tests in 36 suites passed after 1.736 seconds.
Build complete! (10.46s)
exact-path process matching passed
Relay.app: valid on disk
Relay.app: satisfies its Designated Requirement
```

Final staged process evidence:

```text
exact_app_count=1
app_pid=8148
direct_app_server_count=1
8189 8148 /Applications/ChatGPT.app/Contents/Resources/codex app-server --stdio
```

Implementation commit:

```text
ae90fae33a54c66845c0dbbabd9b854c5777b99c
fix: close Relay final rereview residuals
```

No blocking concerns were found. The verified staged app was intentionally left
running with exactly one direct app-server child.

## Main-thread Verification

After the final review returned `Ready to release: Yes`, the primary task ran
the complete verification sequence again.

The first full-suite run exposed a timing-only fixture failure:
`forceKillsAChildThatIgnoresGracefulShutdown` allowed one second for its child
shell to be scheduled and write a PID file. The unchanged test passed 20
consecutive isolated runs, confirming the production transport was not the
failure source. The fixture now uses the same condition-based poll with a
five-second ceiling so a fully parallel suite cannot exhaust the setup window.

Fresh final evidence:

```text
swift test
Test run with 170 tests in 36 suites passed

swift build -c release
Build complete

./script/build_and_run_process_test.sh
exact-path process matching passed

./script/build_and_run.sh --verify
Relay.app: valid on disk
Relay.app: satisfies its Designated Requirement
```

Final runtime inspection:

```text
exact_app_count=1
app_pid=11788
direct_app_server_count=1
app_server_pid=11818
```

The exact staged application remains running.
