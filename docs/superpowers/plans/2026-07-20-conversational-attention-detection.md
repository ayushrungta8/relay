# Conversational Attention Detection Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Promote completed Codex turns that are waiting for a conversational reply into Relay's highest-priority attention state using local rules first and a dedicated Codex classifier for ambiguous messages.

**Architecture:** Monitoring retains the latest completed final answer and stable turn identity. A pure local rule engine classifies clear positives and negatives; an actor-owned coordinator deduplicates ambiguous AI work, persists dismissals, and applies only current results. A dedicated controller-session adapter uses the existing app-server and authentication while keeping classifier context separate from Relay Controller.

**Tech Stack:** Swift 6.2, Swift Concurrency actors and async streams, SwiftUI, Codex app-server JSON-RPC, Foundation `UserDefaults`, Swift Testing.

## Global Constraints

- Support macOS 15 and later; do not add a new package dependency.
- Structured `waitingOnApproval` and `waitingOnUserInput` flags always override inferred state.
- Use `gpt-5.6-terra` with low reasoning effort through the existing Codex app-server connection.
- Never block monitoring publication while an AI classification is running.
- Never submit an inferred reply through approval or question RPC response paths.
- Persist at most the 200 most recent dismissed `(threadID, turnID)` pairs.
- AI failures, malformed output, low confidence, and stale results preserve normal ready behavior.

---

### Task 1: Final-response metadata and local classification

**Files:**
- Create: `Sources/RelayCore/RelayConversationalAttention.swift`
- Modify: `Sources/RelayCore/RelayTaskActivity.swift`
- Modify: `Sources/RelayCodexClient/CodexMonitoringModels.swift`
- Test: `Tests/RelayCoreTests/RelayConversationalAttentionTests.swift`
- Test: `Tests/RelayCoreTests/RelayTaskActivityTests.swift`
- Test: `Tests/RelayCodexClientTests/CodexMonitoringClientTests.swift`

**Interfaces:**
- Produces: `RelayTaskFinalResponse`, `RelayLocalAttentionClassification`, `RelayConversationalAttentionRules.classify(_:)`, `RelayTaskAttentionReason`, and `RelayTaskActivity.settingInferredReplyRequest(_:)`.
- Consumes: decoded app-server turn IDs, item phases, and complete final-answer text.

- [ ] **Step 1: Add failing rule-engine and attention-reason tests**

```swift
@Test(arguments: [
    "Please review the plan and reply approved.",
    "Confirm before I continue.",
    "Tell me when the server is ready.",
])
func explicitGatesNeedReply(_ text: String) {
    #expect(RelayConversationalAttentionRules.classify(text) == .needsReply)
}

@Test func plainCompletionDoesNotNeedReply() {
    #expect(
        RelayConversationalAttentionRules.classify(
            "Implemented the change. All tests pass."
        ) == .doesNotNeedReply
    )
}

@Test func genericQuestionIsAmbiguous() {
    #expect(
        RelayConversationalAttentionRules.classify(
            "Would you like me to add documentation?"
        ) == .ambiguous
    )
}
```

- [ ] **Step 2: Run the focused tests and confirm the missing-type failure**

Run: `swift test --filter RelayConversationalAttentionTests`

Expected: FAIL because `RelayConversationalAttentionRules` does not exist.

- [ ] **Step 3: Add final-response, local classification, and attention-reason types**

```swift
public struct RelayTaskFinalResponse: Sendable, Equatable, Hashable {
    public let turnID: String
    public let text: String
    public let fingerprint: String
}

public enum RelayLocalAttentionClassification: Sendable, Equatable {
    case needsReply
    case doesNotNeedReply
    case ambiguous
}

public enum RelayTaskAttentionReason: Sendable, Equatable, Hashable {
    case structuredInteraction
    case inferredReplyRequest
    case failure
    case unreadCompletion
    case running
    case none
}
```

Implement `RelayConversationalAttentionRules.classify(_:)` by normalizing case and whitespace, checking a fixed list of explicit gate phrases first, returning `.ambiguous` for question or request markers, and returning `.doesNotNeedReply` otherwise. Extend `RelayTaskActivity` with `latestFinalResponse`, `hasInferredReplyRequest`, and `attentionReason`; compute structured interaction before inferred state and expose a copying helper that preserves all existing fields.

- [ ] **Step 4: Decode the complete latest `final_answer` before display truncation**

```swift
struct CodexMonitoringTurnRecord: Decodable {
    let id: String?
    let status: RelayTaskTurnStatus?
    let items: [CodexMonitoringItemRecord]
    let error: CodexMonitoringErrorRecord?
}

struct CodexMonitoringItemRecord: Decodable {
    let type: String
    let phase: String?
    let text: String?
    let command: String?
    let status: String?
}
```

Add `latestFinalResponse` to `CodexMonitoringThreadRecord`. It must use only the newest completed turn with a non-empty `agentMessage` whose phase is `final_answer`, compute a stable SHA-256 hexadecimal fingerprint with CryptoKit, and pass the untruncated text into `RelayTaskActivity`. Preserve the current normalized `latestUpdate` behavior.

- [ ] **Step 5: Run the focused model tests**

Run: `swift test --filter 'RelayConversationalAttentionTests|RelayTaskActivityTests|CodexMonitoringClientTests'`

Expected: PASS.

- [ ] **Step 6: Commit the metadata and local classifier**

```bash
git add Sources/RelayCore Sources/RelayCodexClient/CodexMonitoringModels.swift Tests/RelayCoreTests Tests/RelayCodexClientTests/CodexMonitoringClientTests.swift
git commit -m "feat: classify conversational attention locally"
```

---

### Task 2: Dedicated Codex AI classifier

**Files:**
- Modify: `Sources/RelayBrain/RelayControllerSession.swift`
- Modify: `Sources/RelayCodexBridge/CodexControllerSessionAdapter.swift`
- Create: `Sources/RelayCodexBridge/CodexAttentionClassifier.swift`
- Test: `Tests/RelayCodexBridgeTests/CodexControllerSessionAdapterTests.swift`
- Create: `Tests/RelayCodexBridgeTests/CodexAttentionClassifierTests.swift`

**Interfaces:**
- Consumes: `RelayTaskFinalResponse` and the existing `RelayControllerSession` event stream.
- Produces: `RelayAttentionAIClassifying.classify(_:) async throws -> RelayAIAttentionClassification` and a configurable controller thread name.

- [ ] **Step 1: Add failing tests for parsing, naming, failure, and timeout**

```swift
@Test func acceptsOnlyHighConfidencePositiveJSON() async throws {
    let session = ClassifierSession(answer: """
        {"needs_reply":true,"confidence":"high","reason":"approval gate"}
        """)
    let classifier = CodexAttentionClassifier(session: session)
    let result = try await classifier.classify("Reply approved to continue.")
    #expect(result.needsReply)
}

@Test func malformedOutputThrows() async {
    let classifier = CodexAttentionClassifier(
        session: ClassifierSession(answer: "probably")
    )
    await #expect(throws: CodexAttentionClassifierError.self) {
        try await classifier.classify("Should I proceed?")
    }
}
```

Also assert that `CodexControllerSessionAdapter(threadName: "Relay Attention Classifier")` sends that exact name via `thread/name/set`, and that cancellation sends `turn/interrupt` with the active thread and turn IDs.

- [ ] **Step 2: Run the classifier tests and confirm failure**

Run: `swift test --filter 'CodexAttentionClassifierTests|CodexControllerSessionAdapterTests'`

Expected: FAIL because the classifier and configurable name do not exist.

- [ ] **Step 3: Generalize the controller session safely**

Add `cancelActiveTurn() async` to `RelayControllerSession` with a default no-op implementation for existing test doubles. Add `threadName: String = "Relay Controller"` to both adapter initializers and use it in `thread/name/set`. Implement cancellation with `turn/interrupt`, then finish the local active stream as interrupted even if the interrupt RPC fails.

- [ ] **Step 4: Implement the classifier actor**

```swift
public struct RelayAIAttentionClassification: Sendable, Equatable {
    public let needsReply: Bool
    public let reason: String
}

public protocol RelayAttentionAIClassifying: Sendable {
    func classify(_ text: String) async throws
        -> RelayAIAttentionClassification
}

public actor CodexAttentionClassifier: RelayAttentionAIClassifying {
    public init(
        session: any RelayControllerSession,
        timeout: Duration = .seconds(20)
    )

    public func classify(_ text: String) async throws
        -> RelayAIAttentionClassification
}
```

Use a controller configuration with no dynamic tools, `gpt-5.6-terra`, low effort, and fixed instructions that require one JSON object. Race stream consumption against the timeout; cancel the active classifier turn on timeout. Strip an optional Markdown code fence, decode `needs_reply`, `confidence`, and `reason`, and map anything except `confidence == "high"` to `needsReply == false`.

- [ ] **Step 5: Run the bridge tests**

Run: `swift test --filter 'CodexAttentionClassifierTests|CodexControllerSessionAdapterTests'`

Expected: PASS.

- [ ] **Step 6: Commit the dedicated classifier**

```bash
git add Sources/RelayBrain/RelayControllerSession.swift Sources/RelayCodexBridge Tests/RelayCodexBridgeTests
git commit -m "feat: add dedicated Codex attention classifier"
```

---

### Task 3: Deduplicated inference and persistent dismissals

**Files:**
- Create: `Sources/RelayApp/Monitoring/RelayAttentionInferenceCoordinator.swift`
- Create: `Sources/RelayApp/Monitoring/RelayAttentionDismissalStore.swift`
- Modify: `Sources/RelayApp/Monitoring/RelayActivityReducer.swift`
- Modify: `Sources/RelayApp/Monitoring/RelayActivityStore.swift`
- Create: `Tests/RelayAppTests/RelayAttentionInferenceCoordinatorTests.swift`
- Modify: `Tests/RelayAppTests/RelayActivityReducerTests.swift`
- Modify: `Tests/RelayAppTests/RelayActivityStoreTests.swift`

**Interfaces:**
- Consumes: local classification, `RelayAttentionAIClassifying`, monitoring snapshots, and `RelayTaskFinalResponse`.
- Produces: `RelayAttentionPreparation`, `RelayInferredAttentionUpdate`, `RelayAttentionDismissalStore.inMemory()`, bounded persisted dismissals, and reducer application guarded by turn ID.

- [ ] **Step 1: Add failing coordinator tests**

```swift
@Test func ambiguousTurnIsClassifiedOnceAndCached() async throws {
    let ai = CountingAttentionClassifier(result: .init(
        needsReply: true,
        reason: "direct question"
    ))
    let coordinator = RelayAttentionInferenceCoordinator(
        aiClassifier: ai,
        dismissalStore: .inMemory()
    )
    let first = await coordinator.prepare(tasks: [ambiguousTask])
    let second = await coordinator.prepare(tasks: [ambiguousTask])
    #expect(first.candidates.count == 1)
    #expect(second.candidates.isEmpty)
    let update = await coordinator.classify(first.candidates[0])
    #expect(update?.needsReply == true)
    #expect(await ai.callCount == 1)
}
```

Add tests that local positives require no AI, AI errors cache a negative result, stale turn updates are rejected by the reducer, dismissals survive a new store instance, and only 200 newest dismissal entries remain.

- [ ] **Step 2: Run focused tests and confirm failure**

Run: `swift test --filter 'RelayAttentionInferenceCoordinatorTests|RelayActivityReducerTests|RelayActivityStoreTests'`

Expected: FAIL because coordinator APIs do not exist.

- [ ] **Step 3: Implement bounded dismissal persistence**

Store Codable entries containing `threadID`, `turnID`, and `dismissedAt` under `relay.attention.dismissedTurns.v1`. `dismiss`, `contains`, and load-time pruning must keep the 200 newest unique pairs. Provide an isolated `UserDefaults` suite initializer for tests.

```swift
struct RelayAttentionDismissalStore: Sendable {
    init(defaults: UserDefaults = .standard)
    static func inMemory() -> RelayAttentionDismissalStore
    func contains(threadID: String, turnID: String) -> Bool
    func dismiss(threadID: String, turnID: String, at date: Date = .now)
}
```

- [ ] **Step 4: Implement coordinator preparation and AI caching**

```swift
struct RelayAttentionCandidate: Sendable, Equatable, Hashable {
    let threadID: String
    let response: RelayTaskFinalResponse
}

struct RelayAttentionPreparation: Sendable {
    let tasks: [RelayTaskActivity]
    let candidates: [RelayAttentionCandidate]
}

struct RelayInferredAttentionUpdate: Sendable, Equatable {
    let threadID: String
    let turnID: String
    let needsReply: Bool
}
```

`prepare(tasks:)` applies local positives immediately, respects dismissals and cached results, and reserves each ambiguous key in an `inFlight` set before returning candidates. `classify(_:)` always removes `inFlight`, caches success or failure, and returns an update associated with the original turn.

- [ ] **Step 5: Integrate nonblocking scheduling with activity state**

After each snapshot, call `prepare`, merge and publish its decorated tasks immediately, then launch one unstructured child `Task` per returned candidate. Apply a positive update only when the reducer's current task still has the same final-response turn ID. Track classification tasks for cancellation in `deinit`.

Before `markRead` or `send`, dismiss an inferred task's current turn through the coordinator. Rebuilding the task with `hasInferredReplyRequest: false` clears it immediately; later snapshots respect the persisted dismissal.

- [ ] **Step 6: Run coordinator, reducer, and store tests**

Run: `swift test --filter 'RelayAttentionInferenceCoordinatorTests|RelayActivityReducerTests|RelayActivityStoreTests'`

Expected: PASS.

- [ ] **Step 7: Commit inference state management**

```bash
git add Sources/RelayApp/Monitoring Tests/RelayAppTests
git commit -m "feat: track inferred reply attention"
```

---

### Task 4: Runtime wiring and internal-thread filtering

**Files:**
- Modify: `Sources/RelayCodexBridge/RelayControllerThreadStore.swift`
- Modify: `Sources/RelayApp/RelayAppRuntime.swift`
- Modify: `Sources/RelayApp/Monitoring/RelayActivityReducer.swift`
- Modify: `Sources/RelayApp/Monitoring/RelayActivityStore.swift`
- Modify: `Sources/RelayApp/RelayAppModel.swift`
- Test: `Tests/RelayAppTests/RelayActivityReducerTests.swift`
- Test: `Tests/RelayCodexBridgeTests/RelayControllerThreadStoreTests.swift`

**Interfaces:**
- Consumes: the shared `PersistentCodexAppServerClient` and classifier coordinator initializer from Task 3.
- Produces: a persisted classifier thread identity and a set of internal IDs/names filtered from Relay activity.

- [ ] **Step 1: Add failing internal-thread tests**

Assert that both authoritative IDs and both fallback names (`Relay Controller`, `Relay Attention Classifier`) are excluded while similarly named worker tasks remain visible.

- [ ] **Step 2: Run focused tests and confirm failure**

Run: `swift test --filter 'RelayActivityReducerTests|RelayControllerThreadStoreTests'`

Expected: FAIL because only one controller identity is supported.

- [ ] **Step 3: Add a versioned classifier identity store**

Expose `RelayControllerThreadFileStore.attentionClassifierFileURL`, ending in `attention-classifier-thread-id-v1`, and construct a second `RelayControllerIdentity` from it.

- [ ] **Step 4: Wire the live classifier through the shared app-server**

In `RelayAppRuntime`, construct a second `CodexControllerSessionAdapter` with `threadName: "Relay Attention Classifier"`, wrap it in `CodexAttentionClassifier`, and inject it into `RelayActivityStore`. Pass both thread stores as internal identities. Do not eagerly create the classifier thread; creation occurs on the first ambiguous classification.

- [ ] **Step 5: Generalize filtering**

Change snapshot merging from one optional controller ID to `Set<String>` internal IDs and centralize exact fallback-name matching. Apply the same two-name fallback in `RelayAppModel`'s legacy provider path.

- [ ] **Step 6: Run runtime and filtering tests**

Run: `swift test --filter 'RelayActivityReducerTests|RelayControllerThreadStoreTests|RelayAppModelTests'`

Expected: PASS.

- [ ] **Step 7: Commit live wiring**

```bash
git add Sources/RelayCodexBridge/RelayControllerThreadStore.swift Sources/RelayApp Tests/RelayAppTests Tests/RelayCodexBridgeTests
git commit -m "feat: wire conversational attention classifier"
```

---

### Task 5: Inferred-reply presentation and actions

**Files:**
- Modify: `Sources/RelayApp/Activity/RelaySelectedTaskView.swift`
- Modify: `Sources/RelayApp/Activity/RelayTaskCard.swift`
- Modify: `Sources/RelayApp/Activity/RelayActivityPresentation.swift`
- Modify: `Sources/RelayApp/RelayAccessibilityContract.swift`
- Test: `Tests/RelayAppTests/RelayPendingInteractionPresentationTests.swift`
- Test: `Tests/RelayAppTests/RelayActivityPresentationTests.swift`

**Interfaces:**
- Consumes: `RelayTaskActivity.attentionReason` and existing `RelayTaskActions.send`, `open`, and `markRead` closures.
- Produces: `RelaySelectedTaskCopy.statusTitle(for:)`, `RelaySelectedTaskCopy.explanation(for:)`, and Reply, Open, and Dismiss controls without constructing a `RelayPendingInteraction`.

- [ ] **Step 1: Add failing presentation tests**

```swift
@Test func inferredReplyUsesConversationalPresentation() {
    let task = inferredReplyTask()
    #expect(task.attentionState == .needsInput)
    #expect(task.attentionReason == .inferredReplyRequest)
    #expect(RelaySelectedTaskCopy.statusTitle(for: task) == "Needs your reply")
    #expect(RelaySelectedTaskCopy.explanation(for: task) == "Codex is waiting for your reply.")
}
```

Keep the existing test proving that a genuine external structured request still says it belongs to another Codex client.

Define the tested copy boundary in `RelaySelectedTaskView.swift`:

```swift
struct RelaySelectedTaskCopy {
    static func statusTitle(for task: RelayTaskActivity) -> String
    static func explanation(for task: RelayTaskActivity) -> String?
}
```

- [ ] **Step 2: Run focused presentation tests and confirm failure**

Run: `swift test --filter 'RelayPendingInteractionPresentationTests|RelayActivityPresentationTests'`

Expected: FAIL because inferred requests still enter the structured interaction branch.

- [ ] **Step 3: Branch selected-task actions by reason**

For `.inferredReplyRequest`, render “Codex is waiting for your reply,” begin the existing follow-up composer when the task becomes selected, and show Reply, Open in Codex, and Dismiss. Reply uses `actions.send`; Dismiss uses `actions.markRead`. Return `true` from `allowsTaskManagement` for inferred requests. Only `.structuredInteraction` may create `RelayPendingInteractionPresentation`.

- [ ] **Step 4: Update concise and accessible copy**

Use “Needs your reply” for inferred status, retain “Needs your response” for structured interactions, and ensure VoiceOver includes the same semantic distinction. Compact counts remain the existing “needs you” count.

- [ ] **Step 5: Run presentation tests**

Run: `swift test --filter 'RelayPendingInteractionPresentationTests|RelayActivityPresentationTests|RelayFinalFixContractsTests'`

Expected: PASS.

- [ ] **Step 6: Commit the UI behavior**

```bash
git add Sources/RelayApp/Activity Sources/RelayApp/RelayAccessibilityContract.swift Tests/RelayAppTests
git commit -m "feat: present inferred reply requests"
```

---

### Task 6: Integrated verification

**Files:**
- Modify only files required to fix failures directly caused by Tasks 1–5.

**Interfaces:**
- Consumes: all feature components.
- Produces: a passing repository and evidence that failure paths preserve monitoring behavior.

- [ ] **Step 1: Run formatting and diff checks**

Run: `git diff --check`

Expected: no output and exit code 0.

- [ ] **Step 2: Run all focused feature tests together**

Run: `swift test --filter 'ConversationalAttention|AttentionClassifier|AttentionInference|RelayTaskActivityTests|RelayActivityReducerTests|RelayActivityStoreTests|RelayPendingInteractionPresentationTests'`

Expected: PASS with zero failures.

- [ ] **Step 3: Run the full suite**

Run: `swift test`

Expected: PASS with zero failures.

- [ ] **Step 4: Review final behavior against the design**

Confirm from tests and code inspection that structured requests win, local positives avoid AI, ambiguous messages are classified once, AI failures remain ready, stale results are ignored, dismissals persist, replies clear inferred attention, and internal threads are filtered.

- [ ] **Step 5: Commit any integration-only corrections**

```bash
git add Sources Tests
git commit -m "fix: complete conversational attention integration"
```

Skip this commit when verification required no corrections.
