# Relay Notch Activity Center Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build and launch a notch-native Relay activity center with live Codex
task attention, controls, thread context, account limits, pending handoffs, and
voice/text supervision.

**Architecture:** A long-lived monitoring actor converts Codex app-server reads
and events into presentation-neutral snapshots. `RelayAppModel` owns those
snapshots for SwiftUI, while a narrow AppKit panel controller owns notch
placement and window lifecycle.

**Tech Stack:** Swift 6.2, SwiftUI, AppKit, Swift Testing, Codex app-server v2
JSON-RPC.

## Global Constraints

- Minimum platform is macOS 15.
- Add no third-party runtime dependencies.
- Use test-driven development: every production behavior starts with a failing
  test that is observed before implementation.
- Keep SwiftUI as the source of truth; AppKit owns only panel/window behavior.
- Keep the menu-bar extra as a fallback on every Mac.
- Never hard-code a five-hour or weekly usage window; use backend duration and
  reset fields.
- Never claim an external-client pending request was answered by Relay.
- Status must not depend on color alone.
- Respect Reduce Motion.
- Each independently reviewable task ends in a commit.

---

### Task 1: Codex monitoring models and protocol decoding

**Files:**
- Create: `Sources/RelayCore/RelayTaskActivity.swift`
- Create: `Sources/RelayCore/RelayUsageSnapshot.swift`
- Create: `Sources/RelayCore/RelayThreadTokenUsage.swift`
- Create: `Sources/RelayCodexClient/CodexMonitoringClient.swift`
- Create: `Sources/RelayCodexClient/CodexMonitoringModels.swift`
- Modify: `Sources/RelayCore/CodexThread.swift`
- Test: `Tests/RelayCoreTests/RelayTaskActivityTests.swift`
- Test: `Tests/RelayCodexClientTests/CodexMonitoringClientTests.swift`

**Interfaces:**
- Produces: `RelayTaskActivity`, `RelayTaskAttentionState`,
  `RelayUsageSnapshot`, `RelayRateLimitWindow`, `RelayRateLimitResetCredit`,
  `RelayThreadTokenUsage`, and actor `CodexMonitoringClient`.
- `CodexMonitoringClient.snapshot(limit:) async throws -> RelayMonitoringSnapshot`
- `CodexMonitoringClient.events() -> AsyncStream<RelayMonitoringEvent>`

- [ ] **Step 1: Write failing decoding and priority tests**

Cover active flags, waiting-state priority, both rate-limit windows, reset
credits, missing usage, and context percentage. Use realistic JSON fixtures
matching the generated Codex v2 protocol.

- [ ] **Step 2: Run focused tests and confirm RED**

Run:

```bash
swift test --filter 'RelayTaskActivityTests|CodexMonitoringClientTests'
```

Expected: compilation failure because the monitoring types do not exist.

- [ ] **Step 3: Implement minimal models and RPC reads**

Implement exact decoding for `thread/list`, targeted `thread/read`,
`account/rateLimits/read`, and relevant notifications. Preserve raw
`windowDurationMins`, `usedPercent`, `resetsAt`, `availableCount`,
`activeFlags`, token breakdown, and `modelContextWindow`.

- [ ] **Step 4: Run focused and full tests**

```bash
swift test --filter 'RelayTaskActivityTests|CodexMonitoringClientTests'
swift test
```

Expected: all tests pass with zero failures.

- [ ] **Step 5: Commit**

```bash
git add Sources/RelayCore Sources/RelayCodexClient Tests/RelayCoreTests Tests/RelayCodexClientTests
git commit -m "feat: add Codex activity and usage monitoring"
```

### Task 2: Monitoring store, unread state, and task actions

**Files:**
- Create: `Sources/RelayApp/Monitoring/RelayActivityStore.swift`
- Create: `Sources/RelayApp/Monitoring/RelayActivityReducer.swift`
- Create: `Sources/RelayApp/Monitoring/RelayConnectionState.swift`
- Modify: `Sources/RelayApp/RelayAppRuntime.swift`
- Modify: `Sources/RelayApp/RelayAppModel.swift`
- Modify: `Sources/RelayCodexClient/CodexTaskOperationsClient.swift`
- Test: `Tests/RelayAppTests/RelayActivityReducerTests.swift`
- Test: `Tests/RelayAppTests/RelayActivityStoreTests.swift`

**Interfaces:**
- Consumes: `CodexMonitoringClient` and Task 1 snapshot types.
- Produces: `RelayActivityStore.start()`, `refresh()`, `markRead(threadID:)`,
  `send(threadID:prompt:)`, and `interrupt(threadID:)`.
- Store publishes ordered `attentionTasks`, `runningTasks`, `recentTasks`,
  account usage, connection state, and `lastSelectedThreadID`.

- [ ] **Step 1: Write failing reducer/store tests**

Test attention ordering, unread completion persistence, mark-read behavior,
offline last-known snapshots, and capped reconnect scheduling.

- [ ] **Step 2: Run focused tests and confirm RED**

```bash
swift test --filter 'RelayActivityReducerTests|RelayActivityStoreTests'
```

Expected: compilation failure because the activity store does not exist.

- [ ] **Step 3: Implement the reducer and long-lived store**

Use one persistent app-server client. Merge snapshots and events on an actor,
then publish immutable values on the main actor. Refresh every 30 seconds while
connected and reconnect with delays capped at 30 seconds.

- [ ] **Step 4: Run focused and full tests**

```bash
swift test --filter 'RelayActivityReducerTests|RelayActivityStoreTests'
swift test
```

Expected: all tests pass.

- [ ] **Step 5: Commit**

```bash
git add Sources/RelayApp Sources/RelayCodexClient Tests/RelayAppTests
git commit -m "feat: add Relay activity store and attention state"
```

### Task 3: Notch panel and presentation lifecycle

**Files:**
- Create: `Sources/RelayApp/Notch/RelayPanelPresentation.swift`
- Create: `Sources/RelayApp/Notch/RelayNotchGeometry.swift`
- Create: `Sources/RelayApp/Notch/RelayNotchPanel.swift`
- Create: `Sources/RelayApp/Notch/RelayNotchPanelController.swift`
- Create: `Sources/RelayApp/Notch/RelayNotchPanelHost.swift`
- Modify: `Sources/RelayApp/RelayApplication.swift`
- Test: `Tests/RelayAppTests/RelayNotchGeometryTests.swift`
- Test: `Tests/RelayAppTests/RelayPanelPresentationTests.swift`

**Interfaces:**
- Produces: `RelayPanelPresentation` with `hidden`, `peek`, `compact`, and
  `expanded`.
- `RelayNotchGeometry.frame(for:screenFrame:visibleFrame:safeAreaInsets:leftAuxiliaryArea:rightAuxiliaryArea:) -> CGRect`
- `RelayNotchPanelController.present(_:on:)`, `toggle(on:)`, and `dismiss()`.

- [ ] **Step 1: Write failing geometry and transition tests**

Cover built-in notch geometry, no-notch fallback, external display clamping,
presentation escalation, Escape collapse, and automatic peek non-activation.

- [ ] **Step 2: Run focused tests and confirm RED**

```bash
swift test --filter 'RelayNotchGeometryTests|RelayPanelPresentationTests'
```

Expected: compilation failure because the notch types do not exist.

- [ ] **Step 3: Implement the narrow AppKit bridge**

Use an `NSPanel` hosted by `NSHostingView`. Calculate screen-specific placement
without fixed notch dimensions. Keep peek nonactivating, allow compact and
expanded to become key, install outside-click monitoring, and retain the
menu-bar extra as fallback.

- [ ] **Step 4: Run focused and full tests**

```bash
swift test --filter 'RelayNotchGeometryTests|RelayPanelPresentationTests'
swift test
```

Expected: all tests pass.

- [ ] **Step 5: Commit**

```bash
git add Sources/RelayApp/Notch Sources/RelayApp/RelayApplication.swift Tests/RelayAppTests
git commit -m "feat: add notch-native Relay panel"
```

### Task 4: Attention, activity, and capacity interface

**Files:**
- Create: `Sources/RelayApp/Activity/RelayNotchRootView.swift`
- Create: `Sources/RelayApp/Activity/RelayPeekView.swift`
- Create: `Sources/RelayApp/Activity/RelayCompactActivityView.swift`
- Create: `Sources/RelayApp/Activity/RelayExpandedActivityView.swift`
- Create: `Sources/RelayApp/Activity/RelayTaskCard.swift`
- Create: `Sources/RelayApp/Activity/RelayCapacityStrip.swift`
- Create: `Sources/RelayApp/Activity/RelayUsageDetailView.swift`
- Create: `Sources/RelayApp/Activity/RelayStatusSymbol.swift`
- Modify: `Sources/RelayApp/RelayPalette.swift`
- Test: `Tests/RelayAppTests/RelayActivityPresentationTests.swift`

**Interfaces:**
- Consumes: `RelayAppModel`, ordered task sections, capacity snapshots, and
  panel presentation binding.
- Produces: accessible peek, compact, and expanded SwiftUI surfaces plus task
  open, mark-read, send, and interrupt callbacks.

- [ ] **Step 1: Write failing presentation tests**

Test derived peek copy, priority ordering, capacity labels from backend window
durations, unavailable states, 75/90 warning thresholds, and status symbols
that remain distinguishable without color.

- [ ] **Step 2: Run focused tests and confirm RED**

```bash
swift test --filter RelayActivityPresentationTests
```

Expected: compilation failure because presentation types are absent.

- [ ] **Step 3: Implement the SwiftUI surface**

Follow `DESIGN.md`: top-connected black shell, shallow grouping, no nested
cards, semantic fonts, horizontal compact tray, grouped expanded sections,
monospaced usage values, keyboard actions, VoiceOver labels, and Reduce Motion
fallback.

- [ ] **Step 4: Run focused and full tests**

```bash
swift test --filter RelayActivityPresentationTests
swift test
```

Expected: all tests pass.

- [ ] **Step 5: Commit**

```bash
git add Sources/RelayApp/Activity Sources/RelayApp/RelayPalette.swift Tests/RelayAppTests
git commit -m "feat: add Relay activity and capacity interface"
```

### Task 5: Pending handoffs and conversational supervision

**Files:**
- Create: `Sources/RelayCore/RelayPendingInteraction.swift`
- Create: `Sources/RelayCodexBridge/RelayPendingInteractionBroker.swift`
- Modify: `Sources/RelayCodexBridge/CodexControllerSessionAdapter.swift`
- Modify: `Sources/RelayBrain/RelayDynamicTools.swift`
- Modify: `Sources/RelayBrain/RelayTaskContracts.swift`
- Modify: `Sources/RelayBrain/RelayToolCallRouter.swift`
- Modify: `Sources/RelayApp/RelayAppModel.swift`
- Modify: `Sources/RelayApp/Activity/RelayExpandedActivityView.swift`
- Test: `Tests/RelayCodexBridgeTests/RelayPendingInteractionBrokerTests.swift`
- Test: `Tests/RelayBrainTests/RelayAttentionToolTests.swift`
- Test: `Tests/RelayAppTests/RelayPendingInteractionPresentationTests.swift`

**Interfaces:**
- Produces: pending question/approval models, broker responses for Relay-owned
  JSON-RPC requests, and controller tools `relay_get_attention_inbox` and
  `relay_get_usage`.
- External-client waiting tasks produce an Open in Codex action only.

- [ ] **Step 1: Write failing broker, tool, and presentation tests**

Cover owned question answers, approve/decline values, external-request honesty,
attention inbox output, usage output, selected-task pronoun resolution, and
controller-only safe declines.

- [ ] **Step 2: Run focused tests and confirm RED**

```bash
swift test --filter 'RelayPendingInteractionBrokerTests|RelayAttentionToolTests|RelayPendingInteractionPresentationTests'
```

Expected: compilation failure because pending interaction and new tools are
absent.

- [ ] **Step 3: Implement pending interactions and controller reads**

Retain original server request IDs only for requests received by Relay. Remove
blank automatic answers for worker user-input requests. Add explicit submit and
decline paths, while keeping safe automatic declines for the hidden Relay
controller's own non-interactive operations.

- [ ] **Step 4: Run focused and full tests**

```bash
swift test --filter 'RelayPendingInteractionBrokerTests|RelayAttentionToolTests|RelayPendingInteractionPresentationTests'
swift test
```

Expected: all tests pass.

- [ ] **Step 5: Commit**

```bash
git add Sources/RelayCore Sources/RelayCodexBridge Sources/RelayBrain Sources/RelayApp Tests
git commit -m "feat: add pending handoffs and conversational supervision"
```

### Task 6: Integration, accessibility, release build, and launch

**Files:**
- Modify: `Sources/RelayApp/RelayMenuView.swift`
- Modify: `Sources/RelayApp/Composer/RelayCommandComposerView.swift`
- Modify: `Resources/Info.plist`
- Modify: `scripts/build-local-app.sh`
- Create: `Tests/RelayAppTests/RelayAccessibilityContractTests.swift`
- Create: `docs/release/2026-07-17-notch-activity-center.md`

**Interfaces:**
- Produces: a menu-bar fallback that opens the same app model and notch panel,
  release notes, verified local `.app`, and launched application.

- [ ] **Step 1: Write failing integration/accessibility tests**

Cover menu fallback availability, semantic control labels, keyboard shortcuts,
Reduce Motion selection, and no color-only status.

- [ ] **Step 2: Run focused tests and confirm RED**

```bash
swift test --filter RelayAccessibilityContractTests
```

Expected: tests fail on missing integration contracts.

- [ ] **Step 3: Complete integration and release documentation**

Remove obsolete duplicate menu content while retaining Open Relay, Open Codex,
Settings if present, and Quit. Ensure app startup creates one monitoring
runtime and the notch panel. Document user-visible behavior and known
app-server compatibility expectations.

- [ ] **Step 4: Verify tests and build**

```bash
swift test
swift build -c release
./scripts/build-local-app.sh
```

Expected: zero test failures, successful release compilation, and a built Relay
application bundle.

- [ ] **Step 5: Launch and inspect**

```bash
open -a Relay
```

Verify the process is running, the menu fallback opens the panel, the panel is
top-centered, Codex tasks load, capacity renders, and voice/text controls
remain usable.

- [ ] **Step 6: Commit**

```bash
git add Sources Resources Tests scripts docs/release
git commit -m "release: complete Relay notch activity center"
```
