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
- Let `peek` and `compact` appear without activation. Let `expanded` become key
  so text fields and keyboard actions work.
- Launch into compact mode without a menu-bar extra. Hover or click to expand,
  then return to compact after pointer exit, outside click, or Escape.
- Do not collapse while a pending answer or follow-up is being edited unless
  the user explicitly cancels or submits it.
- Retain the global shortcut as the fallback on every display.
- Respect Reduce Motion.

## Acceptance

The panel launches at the correct top-center position on the built-in display,
can be opened on an external display, accepts keyboard input when expanded,
does not steal focus during automatic peeks, and remains fully usable on a Mac
without a notch.
