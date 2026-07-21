# Relay contributor instructions

## Aim

Relay is a native macOS gateway to Codex: it makes background work glanceable,
surfaces anything that needs the user, supports the smallest useful action in
place, and can hand new work to ordinary Codex tasks. It should remain calm,
fast, and notch-native rather than becoming a second full Codex client.

Read `PRODUCT.md` and `DESIGN.md` before changing product behavior or visual
structure. Treat them as current product constraints, not optional background.

## Working style

- For a clear request, inspect the relevant code and implement it directly.
  Do not introduce mandatory specs, plans, approval gates, worktrees, TDD
  rituals, subagents, or review ceremony unless the user asks or the risk truly
  requires them.
- Prefer the smallest coherent change that solves the observed problem. Avoid
  speculative subsystems and abstractions. Relay often already has most of the
  required machinery.
- Ask a question only when the answer changes the implementation materially
  and cannot be learned from the repository or runtime. For subjective UI
  choices, an interactive demo or a few concrete mockups is usually more useful
  than a prose questionnaire.
- Give concise milestone updates. Lead final handoffs with what changed and
  what was actually verified.
- Preserve unrelated working-tree changes. Inspect `git status` before edits,
  stage only intended files, and never fold another task's uncommitted work
  into a build, commit, merge, or release.
- Do not commit, push, merge, release, install over `/Applications`, create a
  branch, or discard work unless the user asks for that action.

## Product boundaries

- Attention outranks activity; activity outranks history. If Codex is waiting
  for a reply, approval, or user input, Relay must surface that before ordinary
  running or completed work.
- Relay may initiate work by resolving a real project directory and creating a
  normal visible Codex task. After handoff, the controller must become
  available again; do not keep the conversational controller occupied as a
  long-running orchestrator.
- Resolve a task directory from the selected task or an unambiguous known
  project. Validate that it exists and is a directory. Never invent a path.
- Keep structured Codex prompts authoritative. Conversational attention
  inference supplements them: obvious requests may be detected locally,
  ambiguous final answers may use the separate classifier, and failures must
  fall back safely without blocking Relay.
- Use authoritative normalized task state (`running`, `needsInput`, `ready`,
  `failed`, or `idle`). A historical message such as “I’m running tests” is not
  proof that the task is still running.
- Internal controller and classifier tasks must stay hidden from Relay's task
  list and must never classify or monitor themselves.
- Settings belong in the expanded panel, apply immediately, persist through a
  centralized store, and preserve existing behavior as the upgrade default.
- User-facing behavior should follow system preferences where possible. In
  particular, speech locale/voice should derive from Apple Speech and macOS
  language settings, not a contributor's personal locale.

## Codex integration realities

- Relay runs its own `codex app-server`; Codex Desktop runs another process.
  Shared task metadata and rollout logs are visible across processes, but live
  RPC requests such as approvals are owned by the originating connection and
  may not be replayed to Relay.
- For desktop-owned work, enrich state from rollout logs. Detect unresolved
  approval or `request_user_input` calls and clear them when a matching result
  appears. When Relay does not own the live RPC, surface the need and open the
  owning Codex task rather than offering a fake Approve/Decline action.
- Follow-ups to desktop-owned running tasks must reach the owning Codex task;
  do not silently create a disconnected turn.
- Keep classifier traffic in its own persistent session so it cannot pollute
  or block the Relay controller. Cache by turn/fingerprint, reject stale
  results, persist dismissals, and prevent feedback loops.
- Relay Chat displays only the final answer. Never expose commentary, tool
  narration, internal prompts, or classifier/controller instructions.
- The Relay controller is intentionally concise, calm, task-focused, and free
  of generic chatbot greetings, hype, canned pleasantries, and emojis. The
  current intended configuration is `gpt-5.6-luna` at medium reasoning effort;
  preserve that unless the product decision changes.
- When controller instructions or semantics change, bump the controller cache
  or instruction revision so existing installations receive a fresh session.

## macOS UI and interaction

- Native SwiftUI/AppKit behavior is the standard. Respect macOS 15+, semantic
  system text, VoiceOver, keyboard access, contrast, and Reduce Motion.
- On notched displays, use the physical notch as part of the composition:
  content sits to its left and right, the camera area stays empty and black,
  and compact UI adds no visible height below the notch except an explicitly
  approved boundary affordance. Notchless displays need a deliberate fallback.
- Expanded Relay is a bounded top-center overlay. Keep controller-owned panel
  geometry deterministic; internal content scrolls rather than resizing the
  panel from SwiftUI measurements.
- Do not make an animated/resizing view its own hover sensor. Pointer tracking
  must use stable geometry and deduplicated boundary transitions, retaining the
  intended collapse delay.
- Controls must advertise interaction: pointing-hand cursors, disclosure
  indicators, useful labels, and visible focus that fits the design. Prefer
  inline disclosure over a second popup when the information fits.
- Keep color restrained and dark. Use semantic color for status and action,
  avoid nested cards and dead space, and preserve the information density of
  approved references.

## Visual work

- An approved mock, demo, screenshot, or reference is binding. Match hierarchy,
  geometry, density, typography, color, spacing, controls, and overall visual
  weight rather than treating it as loose inspiration.
- Establish a comparison loop early: render the real app with realistic data at
  a comparable crop/scale, compare side by side, list the largest visible
  differences, fix them, and capture again.
- Never claim a visual result is polished, matched, or complete based only on a
  build, tests, accessibility output, or source inspection. Inspect the latest
  changed build itself.
- If the user says they will test or explicitly asks you not to operate the UI,
  stop UI automation and provide a short, exact test checklist instead.
- For visual exploration, prefer a playable/interactive demo over generated
  images when interaction, layout, or motion is the decision being made.

## Build and runtime verification

- Use the narrowest relevant tests while iterating, then run `swift test` once
  at the integration boundary when warranted. A focused failure should fail for
  the intended reason; do not add brittle source-contract tests as a substitute
  for behavior unless no better seam exists.
- Use the repository scripts for app builds and releases. Run
  `script/build_and_run.sh --verify` for the normal local app path; release
  packaging lives under `scripts/`.
- For runtime bugs, verify the actual process and bundle path. Stale or duplicate
  Relay instances can invalidate UI, shortcut, and hover testing. When the user
  asks for a test build, stop only the identified Relay processes, launch one
  intended bundle, and confirm exactly one instance is running.
- Test both notched MacBook and notchless/external-display geometry when a
  change touches panel layout, hover regions, display selection, or compact UI.
- Shortcut work must test real press and release behavior. Relay's reliable
  hold-to-talk path uses lower-level keyboard events and Accessibility
  authorization; Carbon alone is insufficient for Option-only or modifier-only
  hold chords on current macOS.
- Report verification honestly. If the full suite is blocked by unrelated
  user changes, say so, identify the unrelated failure, and report the focused
  evidence that did pass.

## Releases

- Release only from a clean, known source state. If the main workspace contains
  unrelated edits, build from a clean temporary worktree so they cannot leak
  into the DMG.
- A release requires an intentional version/build bump, full relevant tests,
  a universal `arm64` + `x86_64` app, signature validation, DMG mount/content
  validation, SHA-256 verification, Sparkle appcast/signature validation, tag,
  push, and GitHub release asset verification.
- Keep stable asset names (`Relay-macos-universal.dmg` and its `.sha256`) so the
  README can use GitHub's `/releases/latest/download/` URLs without edits on
  every version.
- Relay's current public distribution may be signed but unnotarized. Preserve
  the documented Gatekeeper workaround and do not claim notarization unless it
  was actually performed and verified.

## Repository map

- `Sources/RelayApp`: SwiftUI/AppKit UI, panel lifecycle, monitoring, settings,
  composer, and application runtime.
- `Sources/RelayBrain`: Relay controller instructions, dynamic tools, routing,
  and orchestration policy.
- `Sources/RelayCodexClient`: Codex protocol models, monitoring, rollout-log
  snapshots, and cross-process state enrichment.
- `Sources/RelayCodexBridge`: controller/classifier sessions and Codex-side
  adapters.
- `Sources/RelayCore`: shared task/activity and attention models.
- `Sources/RelayVoice`: global shortcut, microphone, and speech behavior.
- `Tests/*Tests`: focused tests mirroring the source modules.
- `PRODUCT.md`, `DESIGN.md`, and `README.md`: product intent, visual system, and
  public contract.
