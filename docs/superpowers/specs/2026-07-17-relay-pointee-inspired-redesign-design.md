# Relay Pointee-Inspired Redesign

## Goal

Replace Relay's oversized card tray with a compact, notch-connected activity
surface inspired by Pointee's silhouette, restraint, and bounded layout. Relay
keeps its own product hierarchy: attention first, active work second, capacity
third, and conversation available without becoming a second Codex client.

## Reference boundary

The redesign borrows interaction principles from the local Pointee project:

- a black surface that visually continues from the physical camera housing;
- a very small compact state and a deliberately bounded expanded state;
- lower-corner rounding with a flush top edge;
- restrained state color, thin separators, and minimal surface nesting;
- expansion anchored at the top center;
- AppKit-owned panel geometry rather than view-driven window feedback.

Relay will not copy Pointee's branding, wording, single-interaction layout, or
decorative treatments. The result must remain recognizably Relay and scale to
multiple Codex tasks.

## Root cause of the current failure

Relay currently measures SwiftUI content inside the same `NSPanel` that it
resizes from that measurement. The compact horizontal `ScrollView` accepts the
panel's proposed vertical space. During a transition from expanded to compact,
that space can be the previous expanded height. Relay then records the inflated
measurement as the compact content height and resizes the panel back to it.

This feedback loop causes the nearly full-height black panel in the reported
screenshot. It also leaves the compact task carousel stranded in the middle of
empty space and clips the trailing task card.

The controller must own explicit presentation sizes. The hosting view must not
publish its own window sizing constraints. Content may scroll inside a bounded
expanded viewport, but content geometry must never determine the panel's outer
height.

## Presentation model

Relay retains four states with revised roles:

1. **Hidden** — no panel.
2. **Peek** — a transient, nonactivating status capsule for a newly completed,
   failed, or waiting task.
3. **Compact** — a persistent, clickable summary attached to the notch.
4. **Expanded** — the interactive activity center.

### Peek and compact

The compact surface targets 400 by 42 points and widens only if the physical
notch requires it. Its left and right content groups are separated by the
measured camera-housing width plus 12 points of clearance on each side. It
contains:

- one semantic state glyph;
- one short priority summary such as `1 needs you`, `3 running`, or `All clear`;
- an optional quiet secondary count or activity glyph;
- no task cards, capacity strip, carousel, or disclosure copy.

Peek uses the same silhouette and content grammar so automatic notifications do
not introduce another component vocabulary. It never steals focus.

### Expanded

The expanded surface targets 720 by 470 points and clamps to the active
display's visible bounds. It never grows in response to task count. Overflow is
handled by internal scrolling.

Every presentation anchors to the absolute top edge of the target screen,
including notchless and external displays. On a notched display, the top rail
occupies the menu-bar band and reserves the measured camera obstruction as an
empty center column. No label or control may render beneath that obstruction.

The shell has a flush top edge, approximately 28-point lower corners, no native
rectangular window shadow, and a deep near-black surface darker than the first
demo. A subtle Relay
green state treatment may appear at the active status glyph or a one-pixel
bottom highlight; it is never decorative background color.

## Expanded information architecture

### Top rail

The top rail uses three columns: Relay identity and aggregate state on the left,
an empty notch-safe center column derived from live display geometry, and
collapse/open-in-Codex controls on the right. It is one line and does not repeat
the task counts shown below.

### Task rail

A 210–230 point left rail lists tasks as dense rows, ordered by:

1. waiting for user input or approval;
2. failed;
3. unread completion;
4. running;
5. recent idle work.

Each row shows a state glyph, title, and one small piece of metadata. Rows do
not use individual card backgrounds. Selection uses a subtle filled surface
and remains visible for keyboard and VoiceOver users.

### Selected task detail

The main region presents only the selected task:

- status and title;
- latest meaningful update, limited to a few lines;
- project and relative update time;
- context usage when available;
- the smallest relevant actions: open, follow up, interrupt, mark read, or
  answer an interaction owned by Relay.

Pending questions and approvals replace the normal action area inline. They do
not create a second nested card. Externally owned waits continue to offer only
`Open in Codex`.

### Capacity and conversation

A narrow footer shows the 5-hour and weekly windows side by side using label,
percentage, and state. Selecting it reveals reset timing in place without
changing the outer panel size.

The Relay composer occupies one stable row at the bottom. A streamed response
appears immediately above it in a bounded region and scrolls internally when
needed. The composer is visually subordinate until focused.

## Visual system

- Use San Francisco semantic styles and monospaced digits for percentages.
- Use white primary text and system-adaptive secondary hierarchy with at least
  4.5:1 contrast for meaningful copy.
- Reserve Relay green for selection, readiness, and the primary action.
- Use system orange, red, and blue only for attention, failure, and running.
- Never rely on color alone; every state has a symbol and label.
- Use separators and spacing before adding surfaces. Do not nest cards.
- Internal controls use 10–14 point corner radii; only the outer notch shell
  receives the large lower-corner radius.

## Motion and interaction

- Expand from the compact top-center frame into the fixed expanded frame over
  roughly 220–260 milliseconds with an ease-out curve. This is the signature
  motion and must preserve the physical relationship to the notch.
- Collapse reverses the same spatial relationship.
- Content crossfades with no more than an 8-point vertical offset and a brief
  bounded blur during task-detail replacement.
- Waiting state uses a slow breathing status halo. Running state may use a
  three-bar waveform. Context and capacity bars animate only when their values
  change. Row selection shifts no more than 2 points.
- Motion is state feedback, never a looping decorative background or entrance
  sequence.
- Reduce Motion replaces geometry choreography with a short crossfade.
- Compact click, the global shortcut, and the menu-bar command open expanded
  Relay directly.
- Escape and outside click dismiss expanded Relay unless a draft requires an
  explicit decision.
- Keyboard focus begins in the selected task region, not automatically in the
  composer.

## Architecture

### Panel geometry

`RelayNotchPanelController` owns fixed presentation sizes and clamps them using
`RelayNotchGeometry`. `NSHostingView.sizingOptions` is disabled and its safe
area contribution is cleared because Relay handles notch geometry explicitly.
The controller no longer stores or reacts to SwiftUI content-height reports.
It publishes the measured notch width and height to SwiftUI solely for safe
layout; those measurements do not influence the outer panel size.

Peek and compact use the nonactivating panel. Expanded uses the interactive
panel. The existing separation avoids mutating activation style on a visible
window.

### SwiftUI composition

- `RelayNotchRootView` switches presentation content without measuring its
  outer height.
- `RelayCompactActivityView` becomes a single compact status control.
- `RelayExpandedActivityView` becomes a bounded shell containing a task rail,
  selected-task detail, capacity footer, and composer.
- `RelayTaskCard` is split or adapted into row and detail presentations so the
  task list is not a grid of equal cards.
- Selection is explicit SwiftUI state initialized from the app model's current
  or last-interacted task and reconciled when tasks disappear.

No monitoring, protocol, pending-interaction ownership, or task-operation
semantics change as part of the redesign.

## Data flow and state changes

The existing activity snapshot continues to supply ordered task groups,
per-thread context usage, pending interactions, and capacity. The expanded view
derives a selected task ID from that snapshot and passes actions through the
existing `RelayTaskActions` interface.

If the selected task disappears, selection moves to the highest-priority task.
If no tasks remain, the main region shows a compact all-clear state while the
capacity and composer remain available.

Unavailable capacity or context remains explicitly unavailable. Stale and
offline data keeps its existing connection presentation and is never rendered
as current.

## Error handling

- A failed task action displays a concise inline error beside that action.
- A disconnected app-server retains the last-known task rail with the existing
  reconnect control.
- An unavailable selected task is reconciled before rendering detail.
- Long task titles and updates truncate or wrap within their region and never
  resize the panel.
- Large task sets and long streamed answers scroll internally.
- External displays and notchless Macs retain the top-center fallback.

## Accessibility

- Every state row exposes title, status, and recency to VoiceOver.
- Selection is communicated with `.isSelected`, not only a background color.
- Icon-only visual controls retain text labels and help text.
- All interactions are reachable by keyboard with a visible focus state.
- Reduce Motion and Reduce Transparency are respected.
- The layout uses semantic fonts and remains usable with increased text size;
  overflow scrolls rather than growing the panel.

## Verification

Automated coverage will prove:

- compact, peek, and expanded frames remain bounded and deterministic;
- a prior expanded frame cannot contaminate compact sizing;
- hosting-view sizing is controller-owned;
- task ordering and selected-task reconciliation are stable;
- empty, waiting, running, failed, offline, unavailable-usage, and large-list
  presentations remain accessible;
- Reduce Motion selects a crossfade.

Release verification will run the full Swift test suite, a release build, the
process-lifecycle test, and the canonical build-and-run script. Visual QA will
open compact and expanded Relay against live Codex data and capture screenshots
showing the notch attachment, bounded height, task selection, capacity footer,
composer, and dismissal behavior.

## Acceptance criteria

- Compact Relay looks like a small extension of the notch, not a dashboard.
- Expanded Relay stays near 720 by 470 points and contains no large empty area.
- The panel begins at the target screen's absolute top edge on every display.
- Header and compact controls remain outside the measured camera obstruction.
- No task card is partially clipped at the panel boundary.
- The user can identify what needs attention, inspect one task, act, check both
  capacity windows, and ask Relay a question without opening Codex.
- The surface remains calm when all tasks are settled.
- The result is visibly informed by Pointee's restraint and physical geometry
  without becoming a branded copy of Pointee.
