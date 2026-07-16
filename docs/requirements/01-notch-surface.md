# Requirement 1: Notch-native surface

## Outcome

Relay appears to originate from the top-center camera housing on a notched
MacBook and degrades gracefully to a top-center panel on other displays.

## Required behavior

- Own the surface through a dedicated `NSPanel` controller, with SwiftUI
  remaining the source of visual and application state.
- Support `hidden`, `peek`, `compact`, and `expanded` presentation states.
- Position against the screen containing the pointer when manually invoked,
  otherwise against the screen containing the active window.
- Use `NSScreen.safeAreaInsets` and the auxiliary top areas when available;
  never assume a fixed notch size.
- Keep the panel above normal application windows without taking over full
  screen or Spaces.
- Let `peek` appear without activation. Let `compact` and `expanded` become key
  so text fields and keyboard actions work.
- Dismiss on outside click and Escape. Do not dismiss while a pending answer is
  being edited unless the user explicitly cancels.
- Retain the existing menu-bar item as fallback and settings/quit access.
- Respect Reduce Motion.

## Acceptance

The panel launches at the correct top-center position on the built-in display,
can be opened on an external display, accepts keyboard input when expanded,
does not steal focus during automatic peeks, and remains fully usable on a Mac
without a notch.
