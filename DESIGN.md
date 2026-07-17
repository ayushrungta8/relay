# Relay Design System

## Intent

Relay is a compact macOS utility anchored to the physical top-center of the
display. Its visual language is derived from the black camera housing and
macOS system materials, with restrained semantic color used only for state and
action.

## Surface hierarchy

- **Resting:** the compact pill remains visible below the camera safe area.
- **Peek:** a top-centered black capsule below the camera safe area, showing
  one state summary for roughly four seconds without taking keyboard focus.
- **Compact:** a 400-point-wide notch extension with one priority summary and
  a quiet secondary activity count. Its 42-point pill begins below the camera
  and menu-bar obstruction rather than inside it.
- **Expanded:** a fixed 700-by-456-point content surface with a task rail,
  selected-task detail, two capacity windows, and the Relay composer. On a
  notched display, its frame also reserves the top camera safe area so the
  header begins below the physical obstruction.

Panel geometry is controller-owned and deterministic. Internal regions scroll
inside the bounded expanded surface, which never covers more than 70 percent
of the active display's height.

## Color

- Base: an obsidian near-black for the notch-connected shell, tinted slightly
  toward ember violet rather than neutral gray.
- Elevated content: two calibrated near-black surface levels. The task rail is
  slightly lighter than the task detail, so depth is visible without boxed
  cards or prominent separators.
- Primary text: system primary.
- Secondary text: system secondary.
- Accent/progress: Relay coral, currently `RGB(0.98, 0.39, 0.30)`.
- Accent highlight and running: ember amber.
- Needs input: Relay coral with a restrained attention halo.
- Ready: mint.
- Failed: crimson.

The active state may cast a faint, bounded ambient glow into the shell. Large
surfaces remain near-black; semantic color is reserved for attention, progress,
selection, and primary actions.

State is always paired with an icon and label, not color alone.

## Typography

Use San Francisco through SwiftUI semantic styles. Task titles use `.body`;
section labels and metadata use `.caption` sparingly; capacity values use
`.callout.monospacedDigit()`. Avoid display typography and tiny `.caption2`
labels.

## Shape and spacing

The outer panel visually joins the notch with square or nearly square top
corners and 14- to 16-point lower corners. Internal task summaries are grouped
rows or shallow cards with 12-point maximum corner radius. Do not nest cards.
The outer edge uses a fine blue-white rim and a soft lower shadow so the dark
surface remains visible against both dark and light content behind it.

## Motion

Panel transitions use a 180- to 240-millisecond ease-out curve. Expansion grows
from the top-center anchor while content crossfades and translates no more than
8 points. Event peeks do not bounce. Reduce Motion replaces size choreography
with an opacity transition.

## Interaction

- Relay launches directly into compact mode without a menu-bar extra or Dock
  presence.
- Hovering or clicking the compact pill expands Relay. Leaving the surface
  returns it to compact after 300 milliseconds.
- Escape, the global shortcut, and outside clicks toggle expanded Relay back
  to compact.
- A dirty answer or follow-up draft pins the expanded surface until cancelled
  or submitted.
- Automatic peeks never steal focus.
- The global shortcut remains available as the recovery path on every Mac.
