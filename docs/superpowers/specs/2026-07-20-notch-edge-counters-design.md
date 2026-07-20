# Notch Edge Counters

## Goal

Replace Relay's persistent 400-by-42-point compact pill with status counters
that use the existing camera-notch band. On a notched Mac, compact Relay must
add no visible height below the native notch and must show no text.

## Compact presentation

On displays with a camera housing, the compact panel is centered on the
housing and is exactly `safeAreaInsets.top` points high. Its width is the
measured obstruction width plus only the side room required for two compact
targets; it no longer reserves the current 96-point text ears or targets a
400-point width.

The compact surface has no Relay shell, rim, shadow, chevron, or ambient glow.
When there is no activity, it draws nothing, leaving the native notch visually
unchanged. The transparent panel remains available over the notch and the
visible counters remain clickable so the global shortcut and direct compact
interaction can still open expanded Relay.

Two 18-point circular counters sit inside the lower corners of the notch band:

- The left counter represents work that needs attention. `needsInput` uses
  Relay coral; `failed` uses crimson; unread `ready` work uses mint. When more
  than one attention state exists, the highest-priority state determines the
  color and the number is the total number of attention tasks.
- The right counter represents running work in ember amber. Its number is the
  number of running tasks.

Counters are omitted when their count is zero. Values above 9 render as `9+`
so the circles never grow. Color is not the only status channel: the counter's
screen-reader value names its state and count, and failure uses an exclamation
mark when it is the sole attention item. The full compact control exposes the
same aggregate status through VoiceOver as the current labeled pill.

Voice activity temporarily owns the right counter. Listening and processing
use the existing voice semantics in the same 18-point footprint, without
adding a label or changing the panel frame.

## Motion

Motion communicates a transition without making Relay continuously demand
attention:

- A newly appearing attention counter performs one restrained scale-and-fade
  arrival and then rests.
- A failure performs one short horizontal emphasis and then rests.
- A newly completed item briefly resolves to a mint check before settling into
  its unread-ready count or disappearing after it is read.
- The running counter uses a very slow, low-amplitude breathing ring while work
  is active.
- Reduce Motion replaces all movement with a short opacity transition and
  removes the running loop.

No attention, failure, or completion animation loops indefinitely.

## Notchless fallback

An external or notchless display cannot reuse physical notch space. Compact
Relay therefore becomes one quiet 28-point top-centered circular control. It
shows only the highest-priority aggregate count and uses the same semantic
color and accessibility value. Idle uses a low-contrast Relay glyph so the
control remains discoverable; it does not restore the wide text pill.

Peek remains a transient labeled notification and keeps its current geometry.
Expanded Relay is unchanged.

## Architecture

`RelayActivityPresentation` publishes compact counter values separately from
its existing text summaries: attention count and priority state, running
count, and the aggregate accessibility copy. This keeps task aggregation out
of the SwiftUI view.

`RelayCompactSummaryLabel` is replaced by a notch-aware counter layout. The
view selects the two-edge layout when `safeArea.topInset > 0` and the single
fallback control otherwise. Small status-counter views own their one-shot and
running animations.

`RelayNotchGeometry` gives `.compact` notch-aware dimensions distinct from
`.peek`: notch height and obstruction-plus-counter width on a notched display,
and the 28-point fallback footprint on a notchless display. Peek and expanded
geometry do not change.

## Interaction and accessibility

The entire compact panel remains one plain button. Clicking a visible counter
or the notch-sized transparent hit region expands Relay. Hovering the region
continues to use the existing expansion behavior. The global shortcut remains
the recovery path when the idle notch has no visible Relay affordance.

VoiceOver announces the aggregate state, for example "2 need attention, 3
running," and the expansion hint. The counters themselves are hidden from the
accessibility tree to avoid duplicate announcements. Status remains
understandable without color through spoken labels, numerals, position, and
the failure mark.

## Verification

Focused presentation and geometry tests cover aggregation, `9+` formatting,
notched compact height, minimal notched width, and the notchless fallback.
Accessibility tests cover the aggregate value and Reduce Motion behavior.

The changed app must be run on a notched display and captured in idle,
attention-only, running-only, and mixed states. The latest captures must show
that idle Relay adds no pixels below the native notch, both counters fit inside
the notch band without clipping, and expanded Relay still opens reliably.

## Out of scope

This change does not alter peek content, expanded information architecture,
task ordering, automatic peek policy, or the settings model.
