# Pointer Display Following Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make compact Relay follow the pointer between displays after a 500-millisecond dwell while pinning expanded and peek presentations.

**Architecture:** Add an AppKit-independent dwell coordinator that works with stable display identities. `RelayNotchPanelController` translates `NSScreen` values into identities, observes pointer/display changes, and remains the sole owner of panel geometry and relocation animation.

**Tech Stack:** Swift 6.2, AppKit, Swift Concurrency, Swift Testing, macOS 15+

## Global Constraints

- Compact Relay follows after a 500-millisecond pointer dwell on another display.
- Expanded Relay and an existing automatic peek remain pinned.
- Deliberate invocation and a new automatic peek choose the pointer display immediately.
- Relocation is a 160-millisecond opacity crossfade, never a spatial animation between displays.
- Reduce Motion uses opacity only.
- Display identity must not depend on frame equality.
- No display preference is added.
- Existing dirty-draft and voice-setup rules remain unchanged.

## File map

- Create `Sources/RelayApp/Notch/RelayScreenIdentity.swift`: stable `NSScreen` identity and lookup.
- Create `Sources/RelayApp/Notch/RelayPointerDisplayFollower.swift`: cancellable dwell state.
- Create `Tests/RelayAppTests/RelayPointerDisplayFollowerTests.swift`: deterministic policy tests.
- Modify `Sources/RelayApp/Notch/RelayNotchPanelController.swift`: observation, recovery, and relocation.
- Modify `Tests/RelayAppTests/RelayPanelPresentationTests.swift`: real-screen identity and timing contracts.

---

### Task 1: Deterministic pointer-display coordinator

**Files:**
- Create: `Sources/RelayApp/Notch/RelayScreenIdentity.swift`
- Create: `Sources/RelayApp/Notch/RelayPointerDisplayFollower.swift`
- Create: `Tests/RelayAppTests/RelayPointerDisplayFollowerTests.swift`

**Interfaces:**
- Consumes: `RelayPanelPresentation`
- Produces: `RelayScreenIdentity.init(displayID:)`, `init?(screen:)`, `resolve(in:)`, `RelayPointerDisplayFollower.observe(pointerDisplay:currentDisplay:presentation:)`, and `cancel()`

- [ ] **Step 1: Write the failing coordinator tests**

Create `RelayPointerDisplayFollowerTests.swift` with these exact cases:

~~~swift
import Testing
@testable import RelayApp

@MainActor
struct RelayPointerDisplayFollowerTests {
    @Test
    func compactRelocatesAfterDwell() async {
        let sleeper = DisplayFollowSleeper()
        var moves: [RelayScreenIdentity] = []
        let follower = RelayPointerDisplayFollower(
            sleep: { try await sleeper.sleep($0) },
            relocate: { moves.append($0) }
        )
        let current = RelayScreenIdentity(displayID: 1)
        let candidate = RelayScreenIdentity(displayID: 2)

        follower.observe(
            pointerDisplay: candidate,
            currentDisplay: current,
            presentation: .compact
        )
        await sleeper.waitUntilSleeping()
        #expect(await sleeper.requestedDuration() == .milliseconds(500))
        #expect(moves.isEmpty)

        await sleeper.resumeAll()
        for _ in 0..<100 where moves.isEmpty { await Task.yield() }
        #expect(moves == [candidate])
    }

    @Test
    func returningToCurrentDisplayCancelsTheMove() async {
        let sleeper = DisplayFollowSleeper()
        var moves: [RelayScreenIdentity] = []
        let follower = RelayPointerDisplayFollower(
            sleep: { try await sleeper.sleep($0) },
            relocate: { moves.append($0) }
        )
        let current = RelayScreenIdentity(displayID: 1)

        follower.observe(
            pointerDisplay: .init(displayID: 2),
            currentDisplay: current,
            presentation: .compact
        )
        await sleeper.waitUntilSleeping()
        follower.observe(
            pointerDisplay: current,
            currentDisplay: current,
            presentation: .compact
        )
        await sleeper.resumeAll()
        for _ in 0..<20 { await Task.yield() }
        #expect(moves.isEmpty)
    }

    @Test(arguments: [
        RelayPanelPresentation.hidden, .peek, .expanded,
    ])
    func nonCompactPresentationsStayPinned(
        presentation: RelayPanelPresentation
    ) async {
        var moves: [RelayScreenIdentity] = []
        let follower = RelayPointerDisplayFollower(
            sleep: { _ in },
            relocate: { moves.append($0) }
        )
        follower.observe(
            pointerDisplay: .init(displayID: 2),
            currentDisplay: .init(displayID: 1),
            presentation: presentation
        )
        for _ in 0..<20 { await Task.yield() }
        #expect(moves.isEmpty)
    }

    @Test
    func newerCandidateInvalidatesTheStaleTask() async {
        let sleeper = DisplayFollowSleeper()
        var moves: [RelayScreenIdentity] = []
        let follower = RelayPointerDisplayFollower(
            sleep: { try await sleeper.sleep($0) },
            relocate: { moves.append($0) }
        )
        let current = RelayScreenIdentity(displayID: 1)
        let second = RelayScreenIdentity(displayID: 3)

        follower.observe(
            pointerDisplay: .init(displayID: 2),
            currentDisplay: current,
            presentation: .compact
        )
        await sleeper.waitUntilSleeping(count: 1)
        follower.observe(
            pointerDisplay: second,
            currentDisplay: current,
            presentation: .compact
        )
        await sleeper.waitUntilSleeping(count: 2)
        await sleeper.resumeAll()
        for _ in 0..<100 where moves.isEmpty { await Task.yield() }
        #expect(moves == [second])
    }
}

private actor DisplayFollowSleeper {
    private var durations: [Duration] = []
    private var continuations: [CheckedContinuation<Void, any Error>] = []

    func sleep(_ duration: Duration) async throws {
        durations.append(duration)
        try await withCheckedThrowingContinuation {
            continuations.append($0)
        }
    }

    func waitUntilSleeping(count: Int = 1) async {
        while durations.count < count { await Task.yield() }
    }

    func requestedDuration() -> Duration? { durations.last }

    func resumeAll() {
        let pending = continuations
        continuations.removeAll()
        for continuation in pending { continuation.resume() }
    }
}
~~~

- [ ] **Step 2: Confirm the tests fail for missing production types**

~~~bash
swift test --filter RelayPointerDisplayFollowerTests
~~~

Expected: compilation fails because `RelayScreenIdentity` and `RelayPointerDisplayFollower` do not exist.

- [ ] **Step 3: Implement stable screen identity**

Create `RelayScreenIdentity.swift`:

~~~swift
import AppKit

struct RelayScreenIdentity: Hashable, Sendable {
    let displayID: CGDirectDisplayID

    init(displayID: CGDirectDisplayID) {
        self.displayID = displayID
    }

    init?(screen: NSScreen) {
        let key = NSDeviceDescriptionKey("NSScreenNumber")
        guard let number = screen.deviceDescription[key] as? NSNumber else {
            return nil
        }
        displayID = CGDirectDisplayID(number.uint32Value)
    }

    func resolve(in screens: [NSScreen] = NSScreen.screens) -> NSScreen? {
        screens.first { RelayScreenIdentity(screen: $0) == self }
    }
}
~~~

- [ ] **Step 4: Implement the dwell coordinator**

Create `RelayPointerDisplayFollower.swift`:

~~~swift
import Foundation

@MainActor
final class RelayPointerDisplayFollower {
    typealias Sleep = @Sendable (Duration) async throws -> Void

    static let dwellDelay = Duration.milliseconds(500)
    static let relocationDuration: TimeInterval = 0.16

    private let sleep: Sleep
    private let relocate: (RelayScreenIdentity) -> Void
    private var candidate: RelayScreenIdentity?
    private var dwellTask: Task<Void, Never>?

    init(
        sleep: @escaping Sleep = { try await Task.sleep(for: $0) },
        relocate: @escaping (RelayScreenIdentity) -> Void
    ) {
        self.sleep = sleep
        self.relocate = relocate
    }

    func observe(
        pointerDisplay: RelayScreenIdentity?,
        currentDisplay: RelayScreenIdentity?,
        presentation: RelayPanelPresentation
    ) {
        guard presentation == .compact,
              let pointerDisplay,
              pointerDisplay != currentDisplay
        else {
            cancel()
            return
        }
        guard candidate != pointerDisplay else { return }

        cancel()
        candidate = pointerDisplay
        dwellTask = Task { [weak self, sleep] in
            do { try await sleep(Self.dwellDelay) }
            catch { return }
            guard let self, !Task.isCancelled else { return }
            commit(pointerDisplay)
        }
    }

    func cancel() {
        dwellTask?.cancel()
        dwellTask = nil
        candidate = nil
    }

    private func commit(_ display: RelayScreenIdentity) {
        guard candidate == display else { return }
        dwellTask = nil
        candidate = nil
        relocate(display)
    }

    deinit { dwellTask?.cancel() }
}
~~~

- [ ] **Step 5: Run and stabilize the focused tests**

~~~bash
swift test --filter RelayPointerDisplayFollowerTests
~~~

Expected: four tests pass. If the test sleeper retains cancelled continuations, add a cancellation handler to remove them; keep the stale-candidate assertion unchanged.

- [ ] **Step 6: Commit Task 1**

~~~bash
git add Sources/RelayApp/Notch/RelayScreenIdentity.swift Sources/RelayApp/Notch/RelayPointerDisplayFollower.swift Tests/RelayAppTests/RelayPointerDisplayFollowerTests.swift
git commit -m "feat: add pointer display dwell policy"
~~~

---

### Task 2: Integrate following with the notch panel

**Files:**
- Modify: `Sources/RelayApp/Notch/RelayNotchPanelController.swift`
- Modify: `Tests/RelayAppTests/RelayPanelPresentationTests.swift`

**Interfaces:**
- Consumes: Task 1's identity, follower, dwell delay, and relocation duration
- Produces: pointer-screen peeks, compact following, stable display recovery, and crossfade relocation

- [ ] **Step 1: Add identity and timing integration tests**

Append inside `RelayPanelPresentationTests`:

~~~swift
    @Test
    func screenIdentityRoundTripsTheMainDisplay() throws {
        let screen = try #require(NSScreen.main)
        let identity = try #require(RelayScreenIdentity(screen: screen))
        #expect(identity.resolve() === screen)
    }

    @Test
    func pointerFollowingUsesApprovedTiming() {
        #expect(
            RelayPointerDisplayFollower.dwellDelay == .milliseconds(500)
        )
        #expect(RelayPointerDisplayFollower.relocationDuration == 0.16)
    }
~~~

Run `swift test --filter RelayPanelPresentationTests`; expected: PASS.

- [ ] **Step 2: Store stable identity and install monitoring**

Replace `currentScreen` with these properties:

~~~swift
private var currentScreenIdentity: RelayScreenIdentity?
private var globalMouseMoveMonitor: Any?
private var localMouseMoveMonitor: Any?
private var screenParametersObserver: NSObjectProtocol?
private lazy var displayFollower = RelayPointerDisplayFollower(
    relocate: { [weak self] identity in
        self?.relocateCompact(to: identity)
    }
)
~~~

Replace the presentation request handler body with:

~~~swift
presentationState.presentationRequestHandler = { [weak self] value in
    guard let self else { return }
    present(value, on: currentScreenIdentity?.resolve())
}
~~~

In `collapseOneLevel()` and both `pointerHoverChanged(_:)` presentation calls,
replace `on: currentScreen` with `on: currentScreenIdentity?.resolve()`. Call
`installPointerDisplayMonitoring()` immediately after assigning
`panel.contentView` at the end of initialization.

- [ ] **Step 3: Synchronize presentation semantics**

Change automatic peek presentation to:

~~~swift
present(.peek, on: screenContainingPointer())
~~~

After every successful `present`, assign and synchronize:

~~~swift
currentScreenIdentity = RelayScreenIdentity(screen: targetScreen)
synchronizePointerDisplayFollowing()
~~~

In `dismiss()`, set the identity to nil and call `displayFollower.cancel()`.

- [ ] **Step 4: Add pointer observation and display recovery**

Add:

~~~swift
private func installPointerDisplayMonitoring() {
    globalMouseMoveMonitor = NSEvent.addGlobalMonitorForEvents(
        matching: .mouseMoved
    ) { [weak self] _ in
        Task { @MainActor in
            self?.synchronizePointerDisplayFollowing()
        }
    }
    localMouseMoveMonitor = NSEvent.addLocalMonitorForEvents(
        matching: .mouseMoved
    ) { [weak self] event in
        self?.synchronizePointerDisplayFollowing()
        return event
    }
    screenParametersObserver = NotificationCenter.default.addObserver(
        forName: NSApplication.didChangeScreenParametersNotification,
        object: nil,
        queue: .main
    ) { [weak self] _ in
        Task { @MainActor in self?.screenParametersDidChange() }
    }
}

private func synchronizePointerDisplayFollowing() {
    let pointerIdentity = screenContainingPointer().flatMap {
        RelayScreenIdentity(screen: $0)
    }
    displayFollower.observe(
        pointerDisplay: pointerIdentity,
        currentDisplay: currentScreenIdentity,
        presentation: presentation
    )
}

private func screenParametersDidChange() {
    guard presentation != .hidden else { return }
    if let screen = currentScreenIdentity?.resolve() {
        present(presentation, on: screen)
    } else if let fallback = screenContainingPointer() ?? NSScreen.main {
        present(presentation, on: fallback)
    }
}
~~~

Add this matching removal method and call it from `deinit` after the existing
outside-click cleanup:

~~~swift
private func removePointerDisplayMonitoring() {
    displayFollower.cancel()
    if let globalMouseMoveMonitor {
        NSEvent.removeMonitor(globalMouseMoveMonitor)
        self.globalMouseMoveMonitor = nil
    }
    if let localMouseMoveMonitor {
        NSEvent.removeMonitor(localMouseMoveMonitor)
        self.localMouseMoveMonitor = nil
    }
    if let screenParametersObserver {
        NotificationCenter.default.removeObserver(screenParametersObserver)
        self.screenParametersObserver = nil
    }
}
~~~

- [ ] **Step 5: Implement guarded two-phase relocation**

Add `relocateCompact(to:)`. Before moving, require all of the following: presentation is still compact, identity differs from `currentScreenIdentity`, the pointer still resolves to the candidate identity, and the identity still resolves to an attached screen.

Add this method. It recomputes geometry for the target screen, fades the old
panel out, teleports the transparent frame, updates screen-specific safe-area
state, and fades in:

~~~swift
private func relocateCompact(to identity: RelayScreenIdentity) {
    guard
        presentation == .compact,
        identity != currentScreenIdentity,
        let pointerScreen = screenContainingPointer(),
        RelayScreenIdentity(screen: pointerScreen) == identity,
        let targetScreen = identity.resolve()
    else {
        synchronizePointerDisplayFollowing()
        return
    }

    displayFollower.cancel()
    let frame = RelayNotchGeometry.frame(
        for: .compact,
        screenFrame: targetScreen.frame,
        visibleFrame: targetScreen.visibleFrame,
        safeAreaInsets: targetScreen.safeAreaInsets,
        leftAuxiliaryArea: targetScreen.auxiliaryTopLeftArea,
        rightAuxiliaryArea: targetScreen.auxiliaryTopRightArea
    )
    let duration = NSWorkspace.shared
        .accessibilityDisplayShouldReduceMotion
        ? 0.12
        : RelayPointerDisplayFollower.relocationDuration

    NSAnimationContext.runAnimationGroup { context in
        context.duration = duration / 2
        panel.animator().alphaValue = 0
    } completionHandler: { [weak self] in
        Task { @MainActor in
            guard let self, presentation == .compact else { return }
            panel.setFrame(frame, display: true)
            presentationState.notchSafeArea = notchSafeArea(
                for: targetScreen
            )
            currentScreenIdentity = identity
            NSAnimationContext.runAnimationGroup { context in
                context.duration = duration / 2
                panel.animator().alphaValue = 1
            }
        }
    }
}
~~~

Never interpolate the frame between displays. If presentation changes while
the fade-out is running, its normal presentation path owns the panel and the
relocation completion returns without changing geometry.

- [ ] **Step 6: Run formatting, focused tests, and production build**

~~~bash
swift format --in-place Sources/RelayApp/Notch/RelayScreenIdentity.swift Sources/RelayApp/Notch/RelayPointerDisplayFollower.swift Sources/RelayApp/Notch/RelayNotchPanelController.swift Tests/RelayAppTests/RelayPointerDisplayFollowerTests.swift Tests/RelayAppTests/RelayPanelPresentationTests.swift
swift test --filter RelayAppTests
swift build --product RelayApp
~~~

Expected: formatting succeeds, all `RelayAppTests` pass, and the executable builds without concurrency warnings or errors.

- [ ] **Step 7: Verify on two real displays**

Inspect the latest changed build and confirm:

1. Compact Relay moves once after a roughly half-second dwell.
2. A brief boundary crossing causes no movement or flicker.
3. Expanded Relay stays pinned while moving the pointer away and typing.
4. Collapsing resumes following.
5. The global shortcut and a new automatic peek open on the pointer display.
6. Disconnecting Relay's display recovers it on an available display without changing presentation.

Do not claim visual completion if two-display inspection cannot be performed.

- [ ] **Step 8: Commit Task 2**

~~~bash
git add Sources/RelayApp/Notch/RelayNotchPanelController.swift Tests/RelayAppTests/RelayPanelPresentationTests.swift
git commit -m "feat: follow pointer across displays"
~~~

---

### Task 3: Final regression verification

**Files:**
- Modify only if verification exposes a regression.

**Interfaces:**
- Consumes: complete Task 1 and Task 2 implementation
- Produces: package-level and real-interface completion evidence

- [ ] **Step 1: Run the complete package suite once**

~~~bash
swift test
~~~

Expected: all package tests pass with zero failures.

- [ ] **Step 2: Check the final repository state**

~~~bash
git diff --check
git status --short
git log -4 --oneline
~~~

Expected: no whitespace errors, a clean worktree, and the feature commits above the design/plan documentation commits.

- [ ] **Step 3: Report environment limitations honestly**

If two physical displays were unavailable, report the automated checks that passed and leave multi-display visual verification explicitly open. A successful build, geometry test, or single-display capture is not evidence that cross-display UX is complete.
