import AppKit
import RelayVoice
import SwiftUI

enum RelayShortcutPresentation {
    nonisolated static func copy(for shortcut: RelayGlobalShortcut) -> String {
        modifierCopy(shortcut.modifiers) + keyCopy(shortcut.keyCode)
    }

    nonisolated static func isValid(
        keyCode: UInt32?,
        modifiers: RelayShortcutModifiers
    ) -> Bool {
        if let keyCode, keyCode > UInt32(UInt16.max) { return false }
        return !modifiers.isEmpty
    }

    nonisolated private static func modifierCopy(
        _ modifiers: RelayShortcutModifiers
    ) -> String {
        var copy = ""
        if modifiers.contains(.function) { copy += "fn" }
        if modifiers.contains(.control) { copy += "⌃" }
        if modifiers.contains(.option) { copy += "⌥" }
        if modifiers.contains(.shift) { copy += "⇧" }
        if modifiers.contains(.command) { copy += "⌘" }
        return copy
    }

    nonisolated private static func keyCopy(_ keyCode: UInt32?) -> String {
        guard let keyCode else { return "" }
        return keyNames[keyCode] ?? "Key \(keyCode)"
    }

    nonisolated private static let keyNames: [UInt32: String] = [
        0: "A", 1: "S", 2: "D", 3: "F", 4: "H", 5: "G",
        6: "Z", 7: "X", 8: "C", 9: "V", 11: "B", 12: "Q",
        13: "W", 14: "E", 15: "R", 16: "Y", 17: "T", 18: "1",
        19: "2", 20: "3", 21: "4", 22: "6", 23: "5", 24: "=",
        25: "9", 26: "7", 27: "−", 28: "8", 29: "0", 30: "]",
        31: "O", 32: "U", 33: "[", 34: "I", 35: "P", 37: "L",
        38: "J", 39: "'", 40: "K", 41: ";", 42: "\\", 43: ",",
        44: "/", 45: "N", 46: "M", 47: ".", 49: "Space",
        50: "`", 36: "Return", 48: "Tab", 51: "Delete",
        53: "Escape", 123: "←", 124: "→", 125: "↓", 126: "↑",
    ]
}

struct RelayShortcutRecorder: View {
    let shortcut: RelayGlobalShortcut
    let onCommit: (RelayGlobalShortcut) -> Void

    @State private var isRecording = false
    @State private var eventMonitor: Any?
    @State private var captureState = RelayShortcutCaptureState()

    var body: some View {
        Button(isRecording ? "Type shortcut…" : valueCopy) {
            beginRecording()
        }
        .buttonStyle(.bordered)
        .controlSize(.small)
        .accessibilityLabel("Push-to-talk shortcut")
        .accessibilityValue(
            isRecording ? "Recording" : valueCopy
        )
        .accessibilityHint(
            "Press and release modifiers, or press modifiers and a key. Escape cancels. Delete restores Option-Space."
        )
        .onDisappear(perform: endRecording)
    }

    private var valueCopy: String {
        RelayShortcutPresentation.copy(for: shortcut)
    }

    private func beginRecording() {
        endRecording()
        isRecording = true
        captureState = RelayShortcutCaptureState()
        eventMonitor = NSEvent.addLocalMonitorForEvents(
            matching: [.keyDown, .flagsChanged]
        ) { event in
            handle(event)
            return nil
        }
    }

    private func handle(_ event: NSEvent) {
        if event.type == .flagsChanged {
            if let shortcut = captureState.modifiersChanged(
                RelayShortcutModifiers(event.modifierFlags)
            ) {
                commit(shortcut)
            }
            return
        }

        switch event.keyCode {
        case 53:
            endRecording()
        case 51, 117:
            endRecording()
            onCommit(.optionSpace)
        default:
            let modifiers = RelayShortcutModifiers(
                event.modifierFlags
            )
            let keyCode = UInt32(event.keyCode)
            guard let shortcut = captureState.keyDown(
                keyCode: keyCode,
                modifiers: modifiers
            ) else {
                NSSound.beep()
                return
            }
            commit(shortcut)
        }
    }

    private func commit(_ shortcut: RelayGlobalShortcut) {
        endRecording()
        onCommit(shortcut)
    }

    private func endRecording() {
        if let eventMonitor {
            NSEvent.removeMonitor(eventMonitor)
            self.eventMonitor = nil
        }
        isRecording = false
    }
}

private extension RelayShortcutModifiers {
    init(_ flags: NSEvent.ModifierFlags) {
        var value: RelayShortcutModifiers = []
        if flags.contains(.command) { value.insert(.command) }
        if flags.contains(.option) { value.insert(.option) }
        if flags.contains(.control) { value.insert(.control) }
        if flags.contains(.shift) { value.insert(.shift) }
        if flags.contains(.function) { value.insert(.function) }
        self = value
    }
}
