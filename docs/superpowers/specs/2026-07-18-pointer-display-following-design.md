# Pointer Display Following

## Outcome

Relay follows the user between displays instead of remaining on the display
where it launched. The compact panel relocates after the pointer has remained
on another display briefly, while an expanded panel stays put so interaction
is never interrupted.

## Interaction model

- Compact Relay follows the pointer's display after a 500-millisecond dwell.
- Crossing onto another display and returning before the dwell expires does
  not move Relay.
- Expanded Relay stays on its current display while it is open, including
  while a draft, voice setup, or another interaction is active.
- After Relay collapses to compact, it immediately evaluates the current
  pointer display and resumes dwell-based following.
- A deliberate global-shortcut or menu-bar invocation moves Relay immediately
  to the pointer's display before applying the requested presentation.
- Automatic attention peeks appear on the pointer's display. A peek already in
  progress remains on that display for its short lifetime rather than moving.
- Display disconnection relocates a visible panel to the pointer display, or
  the main display when the pointer's display cannot be resolved.

The initial version has no display preference. Following the user is the
default product behavior. A fixed-display preference should only be introduced
if real usage demonstrates a need for it.

## Controller design

`RelayNotchPanelController` remains the sole owner of panel placement. It adds
a lightweight screen-change observer driven by mouse movement and display
configuration changes. The observer resolves screens using stable display
identity rather than frame equality, because display frames can change when
the arrangement changes.

When the panel is compact, detecting a different pointer display starts one
cancellable dwell task. Returning to the current display cancels it. When the
task completes, the controller verifies that the panel is still compact and
the pointer is still on the candidate display, then presents compact Relay on
that display using the existing geometry and transition path.

Peek and expanded presentations do not start follow tasks. Entering either
state cancels an outstanding task. Returning to compact restarts observation
from the pointer's then-current display. Existing dirty-draft dismissal rules
remain unchanged.

Mouse observation should use an event monitor or a modestly throttled AppKit
source. It must not recalculate panel geometry or animate the panel for every
mouse-moved event; work occurs only when the resolved display identity changes.

## Movement

Cross-display relocation uses a short crossfade: fade out on the old display,
set the compact frame on the new display, then fade in. It should take roughly
160 milliseconds and honor Reduce Motion by using the same restrained opacity
change without spatial animation.

The panel never animates through the coordinate space between displays. That
would look slow, cross display bezels, and expose complications in differently
scaled or vertically arranged displays.

## Failure and lifecycle behavior

- If no display contains the pointer, Relay keeps its current display and
  retries on the next observation.
- If the current display disappears, Relay falls back to the pointer display
  and then `NSScreen.main`.
- Mouse and display observers are installed only while the panel controller is
  active and are removed during teardown.
- Repeated events for the same display do nothing.
- A stale dwell task cannot move a panel after its presentation or candidate
  display has changed.

## Verification

Focused controller tests cover dwell start, cancellation, stale-task rejection,
expanded and peek pinning, immediate deliberate invocation, and fallback after
display removal. Screen resolution and follow-policy decisions should be kept
separate from AppKit event monitoring so they can be tested deterministically.

Manual verification uses two displays with different sizes or arrangements:

1. Leave Relay compact and move the pointer to the other display; Relay moves
   once after the dwell.
2. Cross the boundary briefly and return; Relay does not move.
3. Expand Relay, move the pointer away, and interact; Relay remains pinned.
4. Collapse Relay; it follows to the pointer display.
5. Invoke Relay with the global shortcut; it opens immediately on the pointer
   display.
6. Disconnect the display containing Relay; the panel recovers onto an
   available display.
