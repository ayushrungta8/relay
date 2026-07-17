# Relay Pointee Redesign Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace Relay's oversized task-card tray with the approved darker, animated, Pointee-inspired notch overlay.

**Architecture:** AppKit owns deterministic panel frames and publishes measured camera-obstruction geometry to SwiftUI without accepting size feedback from SwiftUI. SwiftUI renders a notch-safe compact summary and a fixed expanded split view with task selection, selected-task detail, capacity, and conversation. Existing monitoring, pending-interaction ownership, task actions, and controller semantics remain unchanged.

**Tech Stack:** Swift 6.2, SwiftUI, AppKit `NSPanel`/`NSHostingView`, Swift Testing, SwiftPM, macOS 15.

## Global Constraints

- Expanded Relay targets exactly 720 by 470 points before display clamping.
- Peek and compact Relay target exactly 400 by 42 points before display clamping.
- Every visible presentation anchors at `screenFrame.maxY`, including notchless and external displays.
- The notch-safe center width is `max(190, measuredObstructionWidth + 24)` points.
- No SwiftUI content measurement may mutate the panel's outer frame.
- Disable `NSHostingView.sizingOptions`, clear `safeAreaRegions`, and let the controller own the host frame.
- Use a flush top edge and 28-point lower corners on expanded Relay; compact uses 15-point lower corners.
- Use deep near-black surfaces and Relay green only for selection, readiness, progress, and primary action.
- Motion communicates panel continuity or state; panel transitions last 220–260 ms and task-detail feedback lasts 140–220 ms.
- Reduce Motion replaces geometry/detail movement with a 120 ms opacity transition and disables looping status motion.
- No new third-party dependencies.
- Preserve Relay's existing pending-interaction ownership, draft-dismissal protection, controller, monitoring, and task-operation behavior.

---

### Task 1: Deterministic absolute-top panel geometry

**Files:**
- Create: `Sources/RelayApp/Notch/RelayNotchSafeArea.swift`
- Create: `Sources/RelayApp/Notch/RelayHostingViewConfiguration.swift`
- Modify: `Sources/RelayApp/Notch/RelayNotchGeometry.swift`
- Modify: `Sources/RelayApp/Notch/RelayNotchPanelController.swift`
- Modify: `Sources/RelayApp/Notch/RelayNotchPanelState.swift`
- Modify: `Sources/RelayApp/Notch/RelayNotchPanelHost.swift`
- Modify: `Tests/RelayAppTests/RelayNotchGeometryTests.swift`
- Modify: `Tests/RelayAppTests/RelayPanelPresentationTests.swift`

**Interfaces:**
- Produces: `RelayNotchSafeArea(topInset:obstructionWidth:)` with `contentClearanceWidth`.
- Produces: `RelayHostingViewConfiguration.apply(to:)`.
- Produces: fixed `RelayNotchGeometry.frame(...)` without a `contentHeight` parameter.
- Produces: `RelayNotchPanelState.notchSafeArea` for SwiftUI consumers.

- [ ] **Step 1: Write failing absolute-top and fixed-size tests**

Add these behaviors to `RelayNotchGeometryTests`:

```swift
@Test
func notchlessOverlayUsesTheAbsoluteScreenTop() {
    let screen = CGRect(x: 0, y: 0, width: 1_920, height: 1_080)
    let visible = CGRect(x: 0, y: 0, width: 1_920, height: 1_055)
    let frame = RelayNotchGeometry.frame(
        for: .compact,
        screenFrame: screen,
        visibleFrame: visible,
        safeAreaInsets: .init(),
        leftAuxiliaryArea: nil,
        rightAuxiliaryArea: nil
    )
    #expect(frame.maxY == screen.maxY)
    #expect(frame.size == CGSize(width: 400, height: 42))
}

@Test
func expandedOverlayUsesTheApprovedBoundedSize() {
    let frame = RelayNotchGeometry.frame(
        for: .expanded,
        screenFrame: CGRect(x: 0, y: 0, width: 1_512, height: 982),
        visibleFrame: CGRect(x: 0, y: 25, width: 1_512, height: 919),
        safeAreaInsets: .init(top: 38, left: 0, bottom: 0, right: 0),
        leftAuxiliaryArea: CGRect(x: 0, y: 944, width: 644, height: 38),
        rightAuxiliaryArea: CGRect(x: 868, y: 944, width: 644, height: 38)
    )
    #expect(frame.maxY == 982)
    #expect(frame.size == CGSize(width: 720, height: 470))
}
```

Replace the content-height test with one asserting that large task content has no input to `frame`.

- [ ] **Step 2: Run the focused tests and verify RED**

Run:

```bash
swift test --filter RelayNotchGeometryTests
```

Expected: FAIL because compact still uses the visible-frame top and legacy dimensions.

- [ ] **Step 3: Write failing safe-area and host-ownership tests**

Add to `RelayPanelPresentationTests`:

```swift
@Test
func cameraObstructionReceivesSideClearance() {
    let safeArea = RelayNotchSafeArea(topInset: 38, obstructionWidth: 224)
    #expect(safeArea.contentClearanceWidth == 248)
    #expect(RelayNotchSafeArea(topInset: 0, obstructionWidth: 0).contentClearanceWidth == 190)
}

@Test
func hostingViewDoesNotPublishWindowSizingConstraints() {
    let host = NSHostingView(rootView: Color.clear)
    RelayHostingViewConfiguration.apply(to: host)
    #expect(host.sizingOptions.isEmpty)
    #expect(host.safeAreaRegions.isEmpty)
    #expect(host.autoresizingMask == [.width, .height])
}
```

- [ ] **Step 4: Run the focused test and verify RED**

Run:

```bash
swift test --filter RelayPanelPresentationTests
```

Expected: FAIL because both new types are absent.

- [ ] **Step 5: Implement the geometry and host ownership**

Create the types with these exact contracts:

```swift
struct RelayNotchSafeArea: Equatable, Sendable {
    static let minimumClearanceWidth = 190.0
    static let horizontalPadding = 24.0
    let topInset: Double
    let obstructionWidth: Double

    var contentClearanceWidth: Double {
        max(Self.minimumClearanceWidth, obstructionWidth + Self.horizontalPadding)
    }
}

enum RelayHostingViewConfiguration {
    static func apply<Content: View>(to host: NSHostingView<Content>) {
        host.sizingOptions = []
        host.safeAreaRegions = []
        host.autoresizingMask = [.width, .height]
    }
}
```

Make `RelayNotchGeometry` always use `screenFrame.maxY`, remove `contentHeight`, and return target sizes `400×42` for peek/compact and `720×470` for expanded before clamping. Remove content-height caches, callbacks, and re-presentation from the controller/state/host. Apply `RelayHostingViewConfiguration` once during controller initialization. Publish safe-area height and obstruction width from the target screen before setting the presentation.

- [ ] **Step 6: Run both focused suites and verify GREEN**

Run:

```bash
swift test --filter RelayNotchGeometryTests
swift test --filter RelayPanelPresentationTests
```

Expected: both suites PASS.

- [ ] **Step 7: Commit**

```bash
git add Sources/RelayApp/Notch Tests/RelayAppTests/RelayNotchGeometryTests.swift Tests/RelayAppTests/RelayPanelPresentationTests.swift Sources/RelayApp/Notch/RelayNotchPanelHost.swift
git commit -m "fix: make Relay panel geometry notch-owned"
```

---

### Task 2: Notch-safe compact shell and presentation tokens

**Files:**
- Create: `Sources/RelayApp/Activity/RelayNotchDropShape.swift`
- Create: `Sources/RelayApp/Activity/RelayRunningGlyph.swift`
- Modify: `Sources/RelayApp/RelayPalette.swift`
- Modify: `Sources/RelayApp/Activity/RelayActivityPresentation.swift`
- Modify: `Sources/RelayApp/Activity/RelayPeekView.swift`
- Modify: `Sources/RelayApp/Activity/RelayCompactActivityView.swift`
- Modify: `Sources/RelayApp/Activity/RelayNotchRootView.swift`
- Modify: `Tests/RelayAppTests/RelayActivityPresentationTests.swift`
- Modify: `Tests/RelayAppTests/RelayAccessibilityContractTests.swift`

**Interfaces:**
- Consumes: `RelayNotchSafeArea.contentClearanceWidth` and `topInset` from Task 1.
- Produces: `RelayActivityPresentation.compactPrimaryCopy`, `compactSecondaryCopy`, and `compactState`.
- Produces: a single compact button with left/right ears and no task carousel.

- [ ] **Step 1: Write failing summary-presentation tests**

Add cases proving these exact outputs:

```swift
#expect(presentationWithOneInput.compactPrimaryCopy == "1 needs you")
#expect(presentationWithOneInput.compactSecondaryCopy == "2 running")
#expect(presentationWithOneInput.compactState == .needsInput)
#expect(allClear.compactPrimaryCopy == "All clear")
#expect(allClear.compactSecondaryCopy == nil)
```

- [ ] **Step 2: Run and verify RED**

Run:

```bash
swift test --filter RelayActivityPresentationTests
```

Expected: FAIL because compact summary properties do not exist.

- [ ] **Step 3: Implement compact summary semantics**

Derive `compactPrimaryCopy` from attention count/state, then running count, then `All clear`. Derive `compactSecondaryCopy` only when another meaningful count remains. Derive `compactState` from the highest-priority task, falling back to `.idle`.

- [ ] **Step 4: Replace the compact carousel with notch-safe ears**

`RelayCompactActivityView` must contain one plain `Button`. Its label uses:

```swift
HStack(spacing: 0) {
    HStack(spacing: 8) {
        RelayStatusSymbol(state: activity.compactState)
        Text(activity.compactPrimaryCopy).lineLimit(1)
    }
    .frame(maxWidth: .infinity, alignment: .leading)

    Color.clear
        .frame(width: safeArea.contentClearanceWidth)
        .accessibilityHidden(true)

    HStack(spacing: 7) {
        if activity.runningTasks.isEmpty == false { RelayRunningGlyph() }
        if let secondary = activity.compactSecondaryCopy { Text(secondary) }
        Image(systemName: "chevron.down")
    }
    .frame(maxWidth: .infinity, alignment: .trailing)
}
.frame(minHeight: max(42, safeArea.topInset))
```

Use the same grammar for peek. Remove task cards and capacity from compact Relay. Add `RelayNotchDropShape(bottomRadius:)`, with a flush top and only lower corners rounded. Apply 15 points in compact/peek and 28 in expanded. Darken palette surfaces by replacing translucent white elevation with calibrated near-black colors; retain semantic colors.

- [ ] **Step 5: Add purposeful compact motion**

`RelayRunningGlyph` renders three two-point bars whose scale changes with a value-scoped animation only when Reduce Motion is false. Waiting status receives a slow opacity/scale halo. The compact-to-expanded root transition remains 220 ms anchored movement or 120 ms opacity under Reduce Motion.

- [ ] **Step 6: Run focused tests and verify GREEN**

Run:

```bash
swift test --filter RelayActivityPresentationTests
swift test --filter RelayAccessibilityContractTests
```

Expected: both suites PASS.

- [ ] **Step 7: Commit**

```bash
git add Sources/RelayApp/Activity Sources/RelayApp/RelayPalette.swift Tests/RelayAppTests/RelayActivityPresentationTests.swift Tests/RelayAppTests/RelayAccessibilityContractTests.swift
git commit -m "feat: add Relay notch-safe compact shell"
```

---

### Task 3: Expanded task rail and selected-task detail

**Files:**
- Create: `Sources/RelayApp/Activity/RelayTaskSelection.swift`
- Create: `Sources/RelayApp/Activity/RelayTaskRail.swift`
- Create: `Sources/RelayApp/Activity/RelayTaskRow.swift`
- Create: `Sources/RelayApp/Activity/RelaySelectedTaskView.swift`
- Create: `Sources/RelayApp/Activity/RelayPendingInteractionView.swift`
- Create: `Sources/RelayApp/Activity/RelayExpandedHeader.swift`
- Create: `Sources/RelayApp/Activity/RelayCapacityFooter.swift`
- Modify: `Sources/RelayApp/Activity/RelayExpandedActivityView.swift`
- Modify: `Sources/RelayApp/Activity/RelayCapacityStrip.swift`
- Modify: `Sources/RelayApp/Composer/RelayCommandComposerView.swift`
- Modify: `Sources/RelayApp/Composer/RelayControllerAnswerView.swift`
- Create: `Tests/RelayAppTests/RelayTaskSelectionTests.swift`
- Modify: `Tests/RelayAppTests/RelayFinalFixContractsTests.swift`

**Interfaces:**
- Consumes: activity ordering, token usage, pending interactions, drafts, and `RelayTaskActions` unchanged.
- Produces: `RelayTaskSelection.resolvedID(preferredID:orderedTasks:) -> String?`.
- Produces: a fixed-height expanded split view with notch-safe header, task rail, selected detail, capacity footer, and composer.

- [ ] **Step 1: Write failing task-selection tests**

Create tests proving:

```swift
#expect(RelayTaskSelection.resolvedID(preferredID: second.id, orderedTasks: [first, second]) == second.id)
#expect(RelayTaskSelection.resolvedID(preferredID: "missing", orderedTasks: [first, second]) == first.id)
#expect(RelayTaskSelection.resolvedID(preferredID: nil, orderedTasks: []) == nil)
```

- [ ] **Step 2: Run and verify RED**

Run:

```bash
swift test --filter RelayTaskSelectionTests
```

Expected: FAIL because `RelayTaskSelection` does not exist.

- [ ] **Step 3: Implement selection and the task rail**

Implement `resolvedID` as a pure function that preserves a live preferred ID and otherwise selects the first ordered task. `RelayTaskRail` uses `LazyVStack`, dense borderless row buttons, and one selected fill. Each row exposes title, status, and relative update time to VoiceOver and adds `.isSelected` when selected. Selecting a row updates local selection and calls `actions.select(task)`.

- [ ] **Step 4: Extract pending interaction UI without semantic changes**

Move the existing `RelayPendingInteractionView` implementation from `RelayExpandedActivityView.swift` into its own file. Preserve question drafts, secret fields, option selection, approval values, resolving state, duplicate-submission protection, inline errors, and external `Open in Codex` behavior exactly.

- [ ] **Step 5: Build selected-task detail**

`RelaySelectedTaskView` renders the selected task's status, title, latest update, project, relative update time, and context bar. It provides direct `Open task` plus only relevant secondary actions. Pending interactions replace the normal action region inline. Follow-up composition continues to use `RelayPanelDraftStore`; dirty drafts retain dismissal protection.

Task changes trigger a 180 ms opacity/5-point/brief-blur transition. Context changes animate over 240 ms. Under Reduce Motion both use 120 ms opacity only.

- [ ] **Step 6: Rewrite the expanded shell**

`RelayExpandedActivityView` becomes a bounded `VStack(spacing: 0)`:

```swift
RelayExpandedHeader(...)
Divider()
HStack(spacing: 0) {
    RelayTaskRail(...).frame(width: 232)
    Divider()
    RelaySelectedTaskView(...).frame(maxWidth: .infinity)
}
.frame(height: 306)
Divider()
RelayCapacityFooter(...)
Divider()
RelayControllerAnswerView(...)
RelayCommandComposerView(...)
```

The header uses left controls, a center `Color.clear.frame(width: safeArea.contentClearanceWidth)`, and right controls. Capacity details and streamed answers scroll inside their allotted regions and never resize the panel. The composer becomes one darker, compact row and keeps all submission-gate behavior.

- [ ] **Step 7: Run focused tests and verify GREEN**

Run:

```bash
swift test --filter RelayTaskSelectionTests
swift test --filter RelayPendingInteractionPresentationTests
swift test --filter CommandComposerStateTests
swift test --filter RelayFinalFixContractsTests
```

Expected: all focused suites PASS.

- [ ] **Step 8: Commit**

```bash
git add Sources/RelayApp/Activity Sources/RelayApp/Composer Tests/RelayAppTests
git commit -m "feat: redesign Relay expanded activity center"
```

---

### Task 4: Integration, visual polish, and release verification

**Files:**
- Modify as required by verified defects: `Sources/RelayApp/Activity/*.swift`
- Modify as required by verified defects: `Sources/RelayApp/Notch/*.swift`
- Modify: `docs/release/2026-07-17-final-verification.md`
- Test: `Tests/RelayAppTests/*.swift`

**Interfaces:**
- Consumes: Tasks 1–3 as one complete panel.
- Produces: a committed, built, signed, launched Relay app with current verification evidence.

- [ ] **Step 1: Run the full automated suite**

```bash
swift test
```

Expected: all tests PASS with zero failures.

- [ ] **Step 2: Build release and verify process lifecycle**

```bash
swift build -c release
./script/build_and_run_process_test.sh
```

Expected: release build and exact-path lifecycle test PASS.

- [ ] **Step 3: Build, sign, launch, and verify**

```bash
./script/build_and_run.sh --verify
```

Expected: `dist/Relay.app` passes its designated requirement, launches, and exactly one staged Relay process remains running with one direct app-server child.

- [ ] **Step 4: Inspect live compact and expanded UI**

Open Relay through its accessible menu-bar item, capture compact and expanded screenshots, and verify:

- the panel's `maxY` equals the target screen's `maxY`;
- the expanded frame is 720×470 unless the display clamps it;
- top controls stay outside the physical camera obstruction;
- compact Relay has no carousel or capacity strip;
- the task rail and selected detail do not clip;
- capacity and composer remain visible;
- task selection, compact/expanded morph, and waiting/running motion are smooth;
- Reduce Motion uses crossfades;
- outside click and Escape retain draft safety.

- [ ] **Step 5: Fix only defects reproduced during verification**

For each defect, add a failing focused test first, verify RED, make the smallest production change, and verify GREEN before re-running Steps 1–4.

- [ ] **Step 6: Record evidence and commit**

Update `docs/release/2026-07-17-final-verification.md` with commands, test counts, frame evidence, runtime PIDs, and any remaining physical-only checks.

```bash
git add Sources Tests docs/release/2026-07-17-final-verification.md
git commit -m "test: verify Relay Pointee redesign"
```
