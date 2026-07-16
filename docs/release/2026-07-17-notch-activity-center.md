# Relay 0.2.0 — Notch activity center

Relay now keeps Codex activity in a top-centered macOS notch panel. The compact
view summarizes active work and capacity; the expanded view groups tasks that
need attention, tasks still running, and recent work. Task cards can open Codex,
send a follow-up, interrupt active work, or mark a completion as read.

Pending Codex questions and approval requests appear directly in Relay. The
expanded composer accepts text commands, while the Option-Space push-to-talk
shortcut continues to route speech through the same Relay controller runtime.

The menu-bar item is a durable fallback rather than a second activity surface.
Choose **Open Relay** (Shift-Command-R) to open the existing notch panel,
**Open Codex** to switch to the installed Codex app, or **Quit**
(Command-Q). Startup creates one shared app model, monitoring connection, and
panel controller.

## Accessibility

- Primary controls expose stable VoiceOver labels and hints.
- Return submits the focused command composer; Escape collapses or dismisses
  the panel; all task actions remain keyboard reachable.
- Reduce Motion replaces anchored movement with crossfades.
- Every task state uses distinct text and an SF Symbol in addition to color.
- System text styles and semantic foreground styles preserve macOS text and
  contrast preferences.

## Compatibility and recovery

This build targets macOS 15 or later and was release-validated on macOS 26.5.1
arm64 with `codex-cli 0.144.2`. Relay uses the locally installed `codex
app-server`; that protocol evolves with Codex, so a future incompatible Codex
build can temporarily leave Relay offline. Relay reports the offline state,
keeps the last known activity snapshot, and reconnects with capped backoff
instead of spawning a new server for every refresh.

The local release bundle is built at `dist/Relay.app`, signed with the configured
OpenClicky Local Development identity, and launched through the project-local
`script/build_and_run.sh` entrypoint.
