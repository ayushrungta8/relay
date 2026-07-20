# Notch Edge Counters Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace Relay's persistent compact text pill with tiny status counters that add no visible height below a MacBook notch.

**Architecture:** `RelayActivityPresentation` will expose typed counter models so aggregation and accessibility copy remain independent of SwiftUI. `RelayNotchGeometry` will size compact presentation independently from peek, while a focused compact-counter view will render either two notch-band counters or one 28-point notchless fallback. The root surface will stop drawing Relay chrome behind the compact notched state.

**Tech Stack:** Swift 6.2, SwiftUI, AppKit `NSPanel`, Swift Testing, macOS 15+

## Global Constraints

- On a notched Mac, compact Relay adds no visible pixels below `safeAreaInsets.top`.
- Compact presentation contains no status text, shell, rim, shadow, chevron, or ambient glow.
- Attention is on the left and running or voice activity is on the right.
- Counts above 9 render as `9+` without enlarging the 18-point counters.
- Attention, failure, and completion motion runs once; only running may loop.
- Reduce Motion replaces movement with opacity and disables running loops.
- Notchless displays use one 28-point top-centered circular fallback.
- Peek and expanded presentation geometry and content remain unchanged.
- The minimum supported platform remains macOS 15 and no dependency is added.

---

## File Map

- Modify `Sources/RelayApp/Activity/RelayActivityPresentation.swift`: define the typed compact counter presentation and derive attention/running counter values from tasks.
- Modify `Tests/RelayAppTests/RelayActivityPresentationTests.swift`: protect aggregation, priority, accessibility copy, failure marking, and `9+` formatting.
- Modify `Sources/RelayApp/Notch/RelayNotchSafeArea.swift`: define the counter footprint and minimal notched compact width.
- Modify `Sources/RelayApp/Notch/RelayNotchGeometry.swift`: give compact presentation notch-aware width and height distinct from peek.
- Modify `Tests/RelayAppTests/RelayNotchGeometryTests.swift`: protect notched compact, notchless fallback, and unchanged peek geometry.
- Create `Sources/RelayApp/Activity/RelayCompactCounterView.swift`: render one semantic counter and own its bounded motion.
- Modify `Sources/RelayApp/Activity/RelayCompactSummaryLabel.swift`: replace text summary with the two-edge and single-fallback layouts.
- Modify `Sources/RelayApp/Activity/RelayCompactActivityView.swift`: retain the single-button interaction and aggregate accessibility value.
- Modify `Sources/RelayApp/Activity/RelayNotchRootView.swift`: make the notched compact shell visually transparent.
- Delete `Sources/RelayApp/Activity/RelayCompactStatusDot.swift`: remove the superseded status-dot implementation.
- Modify `Tests/RelayAppTests/RelayAccessibilityContractTests.swift`: protect motion-policy and compact accessibility behavior.
- Modify `DESIGN.md`: replace the stale 400-by-42 compact specification with the accepted edge-counter behavior.

---

### Task 1: Typed Compact Counter Presentation

**Files:**
- Modify: `Sources/RelayApp/Activity/RelayActivityPresentation.swift`
- Modify: `Tests/RelayAppTests/RelayActivityPresentationTests.swift`

**Interfaces:**
- Consumes: ordered `RelayTaskActivity` values and `RelayTaskAttentionState.priority`.
- Produces: `RelayCompactCounterPresentation`, `compactAttentionCounter`, `compactRunningCounter`, and `compactAccessibilityCopy` for the view task.

- [ ] **Step 1: Add failing counter aggregation tests**

Add these assertions to the existing mixed-state test and add focused formatting tests:

```swift
#expect(
    presentation.compactAttentionCounter
        == RelayCompactCounterPresentation(
            count: 1,
            state: .needsInput
        )
)
#expect(
    presentation.compactRunningCounter
        == RelayCompactCounterPresentation(
            count: 2,
            state: .running
        )
)

@Test
func compactAttentionCounterCombinesAttentionStatesAtHighestPriority() {
    let presentation = RelayActivityPresentation(
        tasks: [
            activity(
                id: "waiting",
                title: "Waiting",
                updatedAt: 300,
                status: .active,
                activeFlags: [.waitingOnUserInput]
            ),
            activity(
                id: "failed",
                title: "Failed",
                updatedAt: 200,
                status: .systemError
            ),
            activity(
                id: "ready",
                title: "Ready",
                updatedAt: 100,
                status: .idle,
                hasUnreadCompletion: true
            ),
        ]
    )

    #expect(presentation.compactAttentionCounter?.count == 3)
    #expect(presentation.compactAttentionCounter?.state == .needsInput)
    #expect(presentation.compactAttentionCounter?.displayValue == "3")
    #expect(
        presentation.compactAccessibilityCopy
            == "1 needs you, 1 failed, 1 ready"
    )
}

@Test
func compactCounterCapsTwoDigitValues() {
    let counter = RelayCompactCounterPresentation(
        count: 14,
        state: .running
    )

    #expect(counter.displayValue == "9+")
}

@Test
func soleFailureUsesFailureMark() {
    let counter = RelayCompactCounterPresentation(
        count: 1,
        state: .failed
    )

    #expect(counter.displayValue == "!")
}
```

- [ ] **Step 2: Run the focused presentation tests and confirm the new API is missing**

Run:

```bash
swift test --filter RelayActivityPresentationTests
```

Expected: compilation fails because `RelayCompactCounterPresentation`, `compactAttentionCounter`, and `compactRunningCounter` do not exist.

- [ ] **Step 3: Add the counter value type and derived properties**

Add this internal value type above `RelayActivityPresentation`:

```swift
struct RelayCompactCounterPresentation: Equatable {
    let count: Int
    let state: RelayTaskAttentionState

    var displayValue: String {
        if state == .failed, count == 1 {
            return "!"
        }
        return count > 9 ? "9+" : String(count)
    }
}
```

Add these properties inside `RelayActivityPresentation`:

```swift
var compactAttentionCounter: RelayCompactCounterPresentation? {
    guard let state = attentionTasks.first?.attentionState else {
        return nil
    }
    return RelayCompactCounterPresentation(
        count: attentionTasks.count,
        state: state
    )
}

var compactRunningCounter: RelayCompactCounterPresentation? {
    guard runningTasks.isEmpty == false else { return nil }
    return RelayCompactCounterPresentation(
        count: runningTasks.count,
        state: .running
    )
}
```

Keep `compactAccessibilityCopy` derived from the existing semantic summaries;
do not derive spoken text from color or symbols. Change its implementation to
include every live semantic summary rather than
only the first two:

```swift
var compactAccessibilityCopy: String {
    compactSummaries.map(\.copy).joined(separator: ", ")
}
```

Retain the old primary and secondary copy properties because peek and existing
presentation consumers still use them.

- [ ] **Step 4: Run the presentation tests**

Run:

```bash
swift test --filter RelayActivityPresentationTests
```

Expected: all `RelayActivityPresentationTests` pass.

- [ ] **Step 5: Commit the presentation model**

```bash
git add Sources/RelayApp/Activity/RelayActivityPresentation.swift Tests/RelayAppTests/RelayActivityPresentationTests.swift
git commit -m "feat: model compact notch counters"
```

---

### Task 2: Compact Geometry That Uses Only the Notch Band

**Files:**
- Modify: `Sources/RelayApp/Notch/RelayNotchSafeArea.swift`
- Modify: `Sources/RelayApp/Notch/RelayNotchGeometry.swift`
- Modify: `Tests/RelayAppTests/RelayNotchGeometryTests.swift`

**Interfaces:**
- Consumes: `safeAreaInsets.top`, measured camera `obstructionWidth`, and `RelayPanelPresentation`.
- Produces: `compactCenterClearanceWidth`, `compactCounterPanelWidth`, and deterministic frames used by `RelayNotchPanelController` without controller changes.

- [ ] **Step 1: Replace the old compact geometry expectations with accepted dimensions**

Keep the existing peek test at 400-or-wider by renaming it to `builtInNotchPeekUsesAuxiliaryAreasAndScreenTop`. Add a compact-specific test:

```swift
@Test
func builtInNotchCompactUsesOnlyTheNotchBand() {
    let safeArea = RelayNotchSafeArea(
        topInset: 38,
        obstructionWidth: 224
    )
    let frame = RelayNotchGeometry.frame(
        for: .compact,
        screenFrame: CGRect(x: 0, y: 0, width: 1_512, height: 982),
        visibleFrame: CGRect(x: 0, y: 25, width: 1_512, height: 919),
        safeAreaInsets: .init(top: 38, left: 0, bottom: 0, right: 0),
        leftAuxiliaryArea: CGRect(x: 0, y: 944, width: 644, height: 38),
        rightAuxiliaryArea: CGRect(x: 868, y: 944, width: 644, height: 38)
    )

    #expect(frame.maxY == 982)
    #expect(frame.height == 38)
    #expect(frame.width == safeArea.compactCounterPanelWidth)
    #expect(frame.width < 400)
}
```

Change the notchless compact expectation to:

```swift
#expect(frame.size == CGSize(width: 28, height: 28))
```

Retain a separate peek assertion of `CGSize(width: 400, height: 42)` on a notchless display so compact changes cannot leak into peek.

- [ ] **Step 2: Run the geometry tests and confirm the old 400-by-42 behavior fails**

Run:

```bash
swift test --filter RelayNotchGeometryTests
```

Expected: compact frame assertions fail because compact still shares peek's 400-by-42 target.

- [ ] **Step 3: Define the minimal counter geometry**

Replace the compact text-ear constants in `RelayNotchSafeArea` with:

```swift
static let compactCounterDiameter = 18.0
static let compactCounterTargetWidth = 32.0
static let notchlessCompactDiameter = 28.0

var compactCenterClearanceWidth: Double {
    max(Self.minimumClearanceWidth, obstructionWidth)
}

var compactCounterPanelWidth: Double {
    compactCenterClearanceWidth
        + 2 * Self.compactCounterTargetWidth
}
```

Keep `contentClearanceWidth` and `minimumCompactPanelWidth` only if peek or expanded code still consumes them. Remove unused compact-text constants after `rg` confirms they have no remaining consumers.

- [ ] **Step 4: Split compact sizing from peek sizing**

In `RelayNotchGeometry.frame`, calculate width and height with presentation-specific switches:

```swift
let safeArea = RelayNotchSafeArea(
    topInset: safeAreaInsets.top,
    obstructionWidth: obstructionWidth
)

let requiredWidth = switch presentation {
case .hidden:
    0
case .peek:
    hasCameraHousing
        ? max(400, safeArea.minimumCompactPanelWidth)
        : 400
case .compact:
    hasCameraHousing
        ? safeArea.compactCounterPanelWidth
        : RelayNotchSafeArea.notchlessCompactDiameter
case .expanded:
    700
}

let contentHeight = switch presentation {
case .hidden:
    0
case .peek:
    42
case .compact:
    hasCameraHousing
        ? safeArea.topInset
        : RelayNotchSafeArea.notchlessCompactDiameter
case .expanded:
    520
}
```

Continue clamping and top-centering with the existing frame code. Do not change peek or expanded values.

- [ ] **Step 5: Run geometry and panel tests**

Run:

```bash
swift test --filter 'RelayNotchGeometryTests|RelayPanelPresentationTests'
```

Expected: both suites pass, including 38-point notched compact height, 28-point notchless fallback, and unchanged peek/expanded frames.

- [ ] **Step 6: Commit compact geometry**

```bash
git add Sources/RelayApp/Notch/RelayNotchSafeArea.swift Sources/RelayApp/Notch/RelayNotchGeometry.swift Tests/RelayAppTests/RelayNotchGeometryTests.swift
git commit -m "feat: fit compact Relay inside notch band"
```

---

### Task 3: Edge Counter UI, Motion, and Accessibility

**Files:**
- Create: `Sources/RelayApp/Activity/RelayCompactCounterView.swift`
- Modify: `Sources/RelayApp/Activity/RelayCompactSummaryLabel.swift`
- Modify: `Sources/RelayApp/Activity/RelayCompactActivityView.swift`
- Modify: `Sources/RelayApp/Activity/RelayNotchRootView.swift`
- Delete: `Sources/RelayApp/Activity/RelayCompactStatusDot.swift`
- Modify: `Tests/RelayAppTests/RelayAccessibilityContractTests.swift`
- Modify: `Tests/RelayAppTests/RelayPanelPresentationTests.swift`

**Interfaces:**
- Consumes: `RelayCompactCounterPresentation`, `RelayVoiceActivity`, `RelayNotchSafeArea`, and `RelayAccessibilityContract.allowsLoopingStatusMotion`.
- Produces: `RelayCompactCounterView` and a text-free `RelayCompactSummaryLabel` that remain wrapped by one accessible button.

- [ ] **Step 1: Add focused source-contract and motion-policy tests**

In `RelayAccessibilityContractTests`, retain the existing Reduce Motion assertions and add:

```swift
@Test
func loopingStatusMotionStopsForReduceMotion() {
    #expect(
        RelayAccessibilityContract.allowsLoopingStatusMotion(
            reduceMotion: false
        )
    )
    #expect(
        !RelayAccessibilityContract.allowsLoopingStatusMotion(
            reduceMotion: true
        )
    )
}
```

In `RelayPanelPresentationTests`, use the established
`relayProjectSource(_:)` helper for this source contract:

```swift
@Test
func nativeNotchCompactSourceRemovesPillChromeAndCopy() throws {
    let label = try relayProjectSource(
        "Sources/RelayApp/Activity/RelayCompactSummaryLabel.swift"
    )
    let root = try relayProjectSource(
        "Sources/RelayApp/Activity/RelayNotchRootView.swift"
    )

    #expect(label.contains("notchedCounters"))
    #expect(!label.contains("Text(primaryCopy)"))
    #expect(!label.contains("chevron.down"))
    #expect(root.contains("usesNativeCompactNotch"))
    #expect(root.contains("compactAwareShellFill"))
}
```

- [ ] **Step 2: Run the focused UI contract tests and confirm they fail**

Run:

```bash
swift test --filter 'RelayAccessibilityContractTests|RelayPanelPresentationTests'
```

Expected: source-contract assertions fail while the old label and shell remain.

- [ ] **Step 3: Create the focused counter view**

Create `RelayCompactCounterView.swift` with a fixed 18-point footprint, semantic color, bounded arrival/failure transitions, and the only allowed loop for `.running`:

```swift
import RelayCore
import SwiftUI

struct RelayCompactCounterView: View {
    let counter: RelayCompactCounterPresentation

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isBreathing = false
    @State private var showsReadyCheck = false

    var body: some View {
        ZStack {
            if counter.state == .running {
                Circle()
                    .stroke(color.opacity(0.30), lineWidth: 1)
                    .scaleEffect(isBreathing ? 1.18 : 0.92)
                    .opacity(isBreathing ? 0.18 : 0.55)
            }

            Circle().fill(color)

            if counter.state == .ready, showsReadyCheck {
                Image(systemName: "checkmark")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(Color.white)
            } else {
                Text(counter.displayValue)
                    .font(.system(
                        size: 10,
                        weight: .semibold,
                        design: .rounded
                    ))
                    .foregroundStyle(Color.white)
                    .minimumScaleFactor(0.78)
                    .lineLimit(1)
            }
        }
        .frame(
            width: RelayNotchSafeArea.compactCounterDiameter,
            height: RelayNotchSafeArea.compactCounterDiameter
        )
        .transition(reduceMotion ? .opacity : .scale.combined(with: .opacity))
        .phaseAnimator(
            counter.state == .failed && !reduceMotion
                ? [0.0, -1.5, 1.5, 0.0]
                : [0.0],
            trigger: counter
        ) { content, offset in
            content.offset(x: offset)
        } animation: { _ in
            .easeOut(duration: 0.09)
        }
        .task(id: counter.state == .running && !reduceMotion) {
            guard counter.state == .running, !reduceMotion else {
                isBreathing = false
                return
            }
            withAnimation(
                .easeInOut(duration: 1.8).repeatForever(
                    autoreverses: true
                )
            ) {
                isBreathing = true
            }
        }
        .task(id: counter) {
            guard counter.state == .ready else {
                showsReadyCheck = false
                return
            }
            showsReadyCheck = true
            try? await Task.sleep(for: .milliseconds(550))
            showsReadyCheck = false
        }
        .accessibilityHidden(true)
    }

    private var color: Color {
        switch counter.state {
        case .needsInput: RelayPalette.needsInput
        case .failed: RelayPalette.failed
        case .ready: RelayPalette.ready
        case .running: RelayPalette.running
        case .idle: RelayPalette.idle
        }
    }
}
```

If Swift rejects the conditional `phaseAnimator` phase arrays due to inferred numeric types, extract a `[CGFloat]` computed property named `failureOffsets`; keep the behavior and public interface unchanged.

- [ ] **Step 4: Replace the compact summary label with notch-aware layouts**

Rewrite `RelayCompactSummaryLabel.body` around these two branches:

```swift
var body: some View {
    Group {
        if safeArea.topInset > 0 {
            notchedCounters
        } else {
            notchlessFallback
        }
    }
    .contentShape(.rect)
}

private var notchedCounters: some View {
    HStack(spacing: 0) {
        counterSlot(activity.compactAttentionCounter, alignment: .trailing)

        Color.clear
            .frame(width: safeArea.compactCenterClearanceWidth)
            .accessibilityHidden(true)

        if voiceActivity.isActive {
            RelayVoiceActivityDot(activity: voiceActivity)
                .scaleEffect(0.9)
                .frame(
                    width: RelayNotchSafeArea.compactCounterDiameter,
                    height: RelayNotchSafeArea.compactCounterDiameter
                )
                .frame(width: RelayNotchSafeArea.compactCounterTargetWidth)
        } else {
            counterSlot(activity.compactRunningCounter, alignment: .leading)
        }
    }
    .frame(height: safeArea.topInset)
    .animation(
        .easeOut(duration: 0.18),
        value: activity.compactAttentionCounter
    )
    .animation(
        .easeOut(duration: 0.18),
        value: activity.compactRunningCounter
    )
}

private var notchlessFallback: some View {
    ZStack {
        Circle().fill(RelayPalette.shell)
        if voiceActivity.isActive {
            RelayVoiceActivityDot(activity: voiceActivity)
        } else if let counter = activity.compactAttentionCounter
            ?? activity.compactRunningCounter {
            RelayCompactCounterView(counter: counter)
        } else {
            Image(systemName: "waveform")
                .font(.caption)
                .foregroundStyle(RelayPalette.tertiaryText)
        }
    }
    .frame(
        width: RelayNotchSafeArea.notchlessCompactDiameter,
        height: RelayNotchSafeArea.notchlessCompactDiameter
    )
}

private func counterSlot(
    _ counter: RelayCompactCounterPresentation?,
    alignment: Alignment
) -> some View {
    ZStack(alignment: alignment) {
        Color.clear
        if let counter {
            RelayCompactCounterView(counter: counter)
        }
    }
    .frame(width: RelayNotchSafeArea.compactCounterTargetWidth)
}
```

Delete all compact status text and chevron code. The containing button in `RelayCompactActivityView` keeps:

```swift
.accessibilityLabel("Open Relay activity center")
.accessibilityValue(
    voiceActivity.isActive
        ? voiceActivity.label
        : activity.compactAccessibilityCopy
)
.accessibilityHint("Expands Relay")
```

- [ ] **Step 5: Remove compact shell chrome only for a native notch**

In `RelayNotchRootView`, derive:

```swift
private var usesNativeCompactNotch: Bool {
    presentation == .compact && safeArea.topInset > 0
}

private var compactAwareShellFill: AnyShapeStyle {
    usesNativeCompactNotch
        ? AnyShapeStyle(Color.clear)
        : shellFill
}
```

Fill `notchShape` with `compactAwareShellFill`, suppress the edge overlay when
`usesNativeCompactNotch` is true, and keep `RelayNotchDropShape` for peek and
expanded. Do not make peek transparent. The notchless circle draws its own
background in `RelayCompactSummaryLabel`.

- [ ] **Step 6: Delete the superseded status dot and run focused tests**

Delete `RelayCompactStatusDot.swift`, then run:

```bash
swift test --filter 'RelayActivityPresentationTests|RelayAccessibilityContractTests|RelayPanelPresentationTests|RelayNotchGeometryTests'
```

Expected: all focused suites pass and no source references `RelayCompactStatusDot`.

- [ ] **Step 7: Build the app target to catch SwiftUI type-checking issues**

Run:

```bash
swift build --product RelayApp
```

Expected: build completes successfully.

- [ ] **Step 8: Commit the compact edge-counter UI**

```bash
git add Sources/RelayApp/Activity Sources/RelayApp/RelayAccessibilityContract.swift Tests/RelayAppTests/RelayAccessibilityContractTests.swift Tests/RelayAppTests/RelayPanelPresentationTests.swift
git commit -m "feat: render compact status at notch edges"
```

---

### Task 4: Design-System Update and Real Visual Verification

**Files:**
- Modify: `DESIGN.md`
- Verify: running `dist/Relay.app`

**Interfaces:**
- Consumes: the completed model, geometry, and SwiftUI work from Tasks 1–3.
- Produces: current durable documentation and direct visual evidence for the accepted zero-waste compact state.

- [ ] **Step 1: Update the durable compact-state documentation**

Replace the resting and compact bullets in `DESIGN.md` with:

```markdown
- **Resting:** on a notched display, Relay adds no visible surface when no task
  is active; the native camera housing remains visually unchanged.
- **Compact:** 18-point semantic counters flank the physical camera housing
  inside the existing menu-bar/notch height. Attention appears on the left and
  running or voice activity on the right. There is no status text, chevron,
  shell, or added height. Notchless displays use a 28-point circular fallback.
```

Update Interaction to say that hovering or clicking the counter/notch hit region expands Relay. Remove the obsolete 400-point width and 42-point compact-height claims. Keep peek at 42 points.

- [ ] **Step 2: Run repository-wide static and behavioral verification**

Run:

```bash
git diff --check
swift test
swift build -c release
```

Expected: no diff errors; all tests pass; release build succeeds.

- [ ] **Step 3: Build and launch the real application**

Run:

```bash
script/build_and_run.sh --verify
```

Expected: `dist/Relay.app` launches and the script verifies exactly one Relay process.

- [ ] **Step 4: Capture and compare the notched compact states**

On a notched display, inspect the real top-center screen at the same crop and scale for:

1. idle;
2. attention only;
3. running only;
4. mixed attention and running;
5. Reduce Motion enabled.

The comparison must establish all of the following from the rendered pixels:

- idle adds no black area below the physical notch;
- the compact frame ends at the bottom of the notch/menu-bar band;
- left and right counters are 18-point circles and are not clipped;
- no text, chevron, shell rim, or glow remains;
- mixed counters stay balanced around the camera obstruction;
- hovering or clicking the compact hit region opens expanded Relay;
- leaving or collapsing returns to the exact compact footprint;
- Reduce Motion shows state changes without looping movement.

If any item fails, fix the visible discrepancy, rerun the focused suite for the changed file, rebuild, and capture the latest changed version again. Do not claim visual completion from geometry tests alone.

- [ ] **Step 5: Verify the notchless fallback**

Move compact Relay to a notchless or external display. Confirm a single 28-point circular control appears at absolute top center, shows only the highest-priority count, remains clickable, and never becomes the old wide pill.

- [ ] **Step 6: Commit documentation and any visual corrections**

```bash
git add DESIGN.md Sources/RelayApp Tests/RelayAppTests
git commit -m "docs: align Relay design with notch counters"
```

- [ ] **Step 7: Record final verification evidence**

Run:

```bash
git status --short
git log -4 --oneline
```

Expected: the working tree is clean and the four feature commits are present. Preserve the final screenshots for the handoff and report any display state that could not be captured.
