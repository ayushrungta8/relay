<div align="center">

# Relay

### Keep Codex in the corner of your eye.

A notch-native activity center and conversational controller for Codex on macOS.

[![macOS 15+](https://img.shields.io/badge/macOS-15%2B-000000?logo=apple&logoColor=white)](https://www.apple.com/macos/)
[![Swift 6.2](https://img.shields.io/badge/Swift-6.2-F05138?logo=swift&logoColor=white)](https://www.swift.org/)
[![Latest release](https://img.shields.io/github/v/release/ayushrungta8/relay?display_name=tag&sort=semver)](https://github.com/ayushrungta8/relay/releases/latest)

[Download Relay](https://github.com/ayushrungta8/relay/releases/latest/download/Relay-macos-universal.dmg) · [How it works](#how-it-works) · [Build from source](#build-from-source)

</div>

---

Relay turns the hidden state of your Codex work into a calm, glanceable surface at the top of your screen. See what is running, what needs you, what finished, and how much capacity remains—without bouncing between tasks all day.

It is intentionally **not another Codex client**. Relay gives you the smallest useful action in place, then gets out of the way.

## Everything that needs your attention. Nothing that doesn't.

- **See every active task at a glance.** Running, waiting, completed, and failed work is ranked by what matters now.
- **Handle questions and approvals in place.** Respond to pending Codex interactions without hunting for the right task.
- **Stay on top of capacity.** Track account limits and context consumption before they interrupt your flow.
- **Control work without opening Codex.** Send follow-ups, interrupt a run, mark results as read, or jump into the full task.
- **Ask Relay by voice or text.** Hold Option-Space to talk, or use the built-in composer for a quiet command.
- **Stay informed without being interrupted.** Automatic peeks surface important changes without stealing focus.

## Designed like it belongs on your Mac

Relay lives beneath the camera housing as a compact, always-available status surface. Hover or click to expand into a focused activity center; leave it alone and it stays quiet.

- Native SwiftUI and AppKit—no embedded browser and no third-party runtime
- Keyboard-accessible controls and meaningful VoiceOver labels
- Semantic status icons that do not rely on color alone
- Reduced-motion support and system typography throughout
- Honest offline state with automatic reconnection

## Install

Relay requires **macOS 15 or later** and a local, authenticated Codex installation. It can use Codex from the Codex or ChatGPT desktop app, Homebrew, or your `PATH`.

1. Download [`Relay-macos-universal.dmg`](https://github.com/ayushrungta8/relay/releases/latest/download/Relay-macos-universal.dmg) from the latest GitHub release.
2. Open the DMG and drag **Relay** into **Applications**.
3. Because this free build is not notarized by Apple, remove the download quarantine once:

```bash
xattr -dr com.apple.quarantine /Applications/Relay.app
open /Applications/Relay.app
```

Only do this for a DMG downloaded from this repository. You can verify the download before installing:

```bash
shasum -a 256 -c Relay-macos-universal.dmg.sha256
```

If you prefer not to use Terminal, try opening Relay once, then go to **System Settings → Privacy & Security → Open Anyway**.

On first use, macOS may ask for:

- **Microphone** and **Speech Recognition**, used only while you hold the push-to-talk shortcut
- **Accessibility**, used when Relay needs to bring Codex forward or hand a follow-up to the desktop app

## Shortcuts

| Shortcut | Action |
| --- | --- |
| <kbd>⌥</kbd> <kbd>Space</kbd> | Hold to speak to Relay |
| <kbd>⇧</kbd> <kbd>⌘</kbd> <kbd>R</kbd> | Open or collapse Relay |
| <kbd>Return</kbd> | Send the focused command |
| <kbd>Esc</kbd> | Collapse or dismiss the panel |

Relay will not discard an unfinished answer or follow-up when you press Escape or click away.

## How it works

Relay connects to the `codex app-server` already installed on your Mac. It translates that local task stream into a small set of useful states, keeps the latest snapshot available during reconnects, and sends your actions back through Codex's own protocol.

Your microphone audio is handled by Apple's system audio and speech frameworks, with on-device recognition when the current locale supports it. Relay has no separate account, analytics service, cloud backend, or third-party runtime dependency.

## Build from source

You will need macOS 15+, Xcode 26 or a compatible Swift 6.2+ toolchain, and Git.

```bash
git clone https://github.com/ayushrungta8/relay.git
cd relay
swift test
swift build -c release --arch arm64 --arch x86_64
```

The package contains the `RelayApp` executable plus focused libraries for the app UI, Codex protocol, controller, voice input, and shared task models. See [`Package.swift`](Package.swift) for the complete target graph.

## Project status

Relay is at the beginning of its public life. The core experience is ready for daily use, but Codex's local app-server protocol can evolve. If a future Codex update temporarily breaks compatibility, Relay will show an offline state rather than pretending your tasks are current.

Bug reports and focused feature requests are welcome in [GitHub Issues](https://github.com/ayushrungta8/relay/issues).

---

<div align="center">

Built for people who would rather supervise the work than babysit the window.

</div>
