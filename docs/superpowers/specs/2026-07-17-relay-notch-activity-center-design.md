# Relay Notch Activity Center

## Goal

Expand Relay from a menu-bar task list into a notch-native Codex activity center
without duplicating the full Codex client.

## Product boundary

Relay owns glanceable status, attention routing, capacity visibility, brief
task controls, and conversational supervision. Codex continues to own full
transcripts, diffs, project navigation, configuration, and complex approval
detail.

## Architecture

`RelayCodexClient` gains strongly typed monitoring calls and event decoding.
`RelayCore` owns presentation-neutral activity, usage, token, and pending-state
models. A long-lived monitoring actor reconciles initial reads, notifications,
and periodic refresh into immutable snapshots.

`RelayAppModel` remains the main-actor source of truth for SwiftUI. A narrow
AppKit `RelayNotchPanelController` owns a purpose-built `NSPanel`, display
selection, placement, activation, dismissal, and presentation-state
transitions. The panel hosts SwiftUI content and does not duplicate model
state.

The interface has progressive presentation states:

1. `hidden`
2. `peek`
3. `compact`
4. `expanded`

The attention priority is:

1. waiting on user input or approval
2. failed or blocked
3. completed with unread activity
4. running
5. idle/recent

## Data flow

App-server reads and notifications → monitoring actor → normalized snapshot →
`RelayAppModel` → notch SwiftUI views. User actions flow back through explicit
task, pending-interaction, and controller interfaces.

Initial synchronization uses `thread/list`, targeted `thread/read`,
`account/rateLimits/read`, and `account/usage/read`. Live changes use
`thread/status/changed`, `thread/tokenUsage/updated`,
`account/rateLimits/updated`, turn/item notifications, and server requests
owned by Relay. A periodic refresh repairs missed notifications.

## Error handling

Snapshots carry freshness and connection state. An app-server disconnect keeps
the last known values visible with an offline label and starts capped
reconnection. Unsupported or absent fields are represented as unavailable.
Relay never fabricates progress, remaining capacity, or the ability to answer a
pending request owned by another client.

## Testing

Protocol fixtures cover current app-server payloads. Pure reducers cover state
priority, unread transitions, usage thresholds, context calculations, and
presentation decisions. Panel geometry is isolated behind testable display
inputs. App model tests cover user actions and error recovery. Final
verification includes the complete Swift test suite, release build, launch, and
manual interaction with the installed Codex app.

## Requirement documents

- `docs/requirements/01-notch-surface.md`
- `docs/requirements/02-task-activity-and-attention.md`
- `docs/requirements/03-context-and-account-capacity.md`
- `docs/requirements/04-pending-user-handoffs.md`
- `docs/requirements/05-conversational-control.md`
- `docs/requirements/06-release-quality.md`
