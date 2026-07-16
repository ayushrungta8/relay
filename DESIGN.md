# Relay Design System

## Intent

Relay is a compact macOS utility anchored to the physical top-center of the
display. Its visual language is derived from the black camera housing and
macOS system materials, with restrained semantic color used only for state and
action.

## Surface hierarchy

- **Resting:** no visible panel beyond the normal menu-bar fallback.
- **Peek:** a top-centered black capsule showing one state summary for roughly
  four seconds without taking keyboard focus.
- **Compact:** a 560-point-wide activity tray with horizontally scrollable task
  summaries and a single account-capacity strip.
- **Expanded:** a 680-point-wide control surface with attention inbox, active
  tasks, capacity, and the Relay composer.

The compact and expanded heights are content-driven and clamped to the visible
screen. The panel never covers more than 70 percent of the active display's
height.

## Color

- Base: system black for the notch-connected shell.
- Elevated content: macOS dark material or calibrated near-black system
  surfaces.
- Primary text: system primary.
- Secondary text: system secondary.
- Accent/action: Relay green, currently `RGB(0.18, 0.48, 0.30)`.
- Running: system blue.
- Needs input: system orange.
- Ready: Relay green.
- Failed: system red.

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

## Motion

Panel transitions use a 180- to 240-millisecond ease-out curve. Expansion grows
from the top-center anchor while content crossfades and translates no more than
8 points. Event peeks do not bounce. Reduce Motion replaces size choreography
with an opacity transition.

## Interaction

- Click the menu-bar item or press the configured shortcut to toggle compact
  Relay.
- Click the compact header or a task to expand.
- Escape collapses one level, then dismisses.
- Clicking outside dismisses unless a user question is actively being edited.
- Automatic peeks never steal focus.
- The menu-bar extra remains available on displays without a notch and as a
  recovery path on every Mac.
