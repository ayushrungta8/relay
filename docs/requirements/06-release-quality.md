# Requirement 6: Release quality

## Outcome

Relay is a dependable menu-bar utility that can remain running throughout a
workday.

## Required behavior

- Maintain Swift 6.2 concurrency correctness and the macOS 15 deployment floor.
- Add no third-party runtime dependency.
- Keep each major Swift type in its own file.
- Unit-test protocol decoding, state ranking, unread tracking, usage formatting,
  panel geometry, and command routing.
- Verify keyboard navigation, VoiceOver labels, Reduce Motion, and
  differentiate-without-color behavior.
- Bound refresh work and avoid spawning a new app-server process for every UI
  refresh.
- Reconnect after app-server failure with capped exponential backoff.
- Preserve honest offline state and the last known snapshot.
- Build a signed local `.app` through `scripts/build-local-app.sh`, replace the
  previous local build, and launch the verified bundle.
- Commit each independently reviewable requirement and finish with a clean
  worktree.

## Acceptance

`swift test` passes, the release build succeeds, the built application launches,
the panel can be exercised against the installed Codex app, and `git status`
is clean.
