import AppKit
import ApplicationServices
import Foundation
import RelayCore

enum CodexDesktopFollowUpError: Error, Equatable {
    case accessibilityRequired
    case couldNotOpenThread
    case desktopDidNotActivate
    case keyboardEventUnavailable
}

extension CodexDesktopFollowUpError: LocalizedError {
    var errorDescription: String? {
        switch self {
        case .accessibilityRequired:
            "Allow Relay in System Settings › Privacy & Security › Accessibility, then send the follow-up again."
        case .couldNotOpenThread:
            "Relay could not open this task in Codex Desktop."
        case .desktopDidNotActivate:
            "Codex Desktop did not become ready for the follow-up."
        case .keyboardEventUnavailable:
            "Relay could not create the keyboard event needed to submit the follow-up."
        }
    }
}

@MainActor
struct CodexDesktopFollowUpSender {
    typealias Sleep = @Sendable (Duration) async throws -> Void

    private let isAccessibilityTrusted: () -> Bool
    private let openURL: (URL) -> Bool
    private let frontmostBundleIdentifier: () -> String?
    private let typeAndSubmit: @MainActor (String) throws -> Void
    private let sleep: Sleep

    init(
        isAccessibilityTrusted: @escaping () -> Bool = {
            AXIsProcessTrustedWithOptions([
                "AXTrustedCheckOptionPrompt": true,
            ] as CFDictionary)
        },
        openURL: @escaping (URL) -> Bool = NSWorkspace.shared.open,
        frontmostBundleIdentifier: @escaping () -> String? = {
            NSWorkspace.shared.frontmostApplication?.bundleIdentifier
        },
        typeAndSubmit: @escaping @MainActor (String) throws -> Void = Self.post,
        sleep: @escaping Sleep = { duration in
            try await Task.sleep(for: duration)
        }
    ) {
        self.isAccessibilityTrusted = isAccessibilityTrusted
        self.openURL = openURL
        self.frontmostBundleIdentifier = frontmostBundleIdentifier
        self.typeAndSubmit = typeAndSubmit
        self.sleep = sleep
    }

    func send(threadID: String, prompt: String) async throws {
        guard isAccessibilityTrusted() else {
            throw CodexDesktopFollowUpError.accessibilityRequired
        }
        guard let url = CodexDeepLink.thread(id: threadID), openURL(url) else {
            throw CodexDesktopFollowUpError.couldNotOpenThread
        }

        var activated = false
        for _ in 0..<30 {
            if frontmostBundleIdentifier() == "com.openai.codex" {
                activated = true
                break
            }
            try await sleep(.milliseconds(100))
        }
        guard activated else {
            throw CodexDesktopFollowUpError.desktopDidNotActivate
        }

        try await sleep(.milliseconds(350))
        try typeAndSubmit(prompt)
    }

    private static func post(_ prompt: String) throws {
        guard let source = CGEventSource(stateID: .combinedSessionState),
              let keyDown = CGEvent(
                  keyboardEventSource: source,
                  virtualKey: 0,
                  keyDown: true
              ),
              let keyUp = CGEvent(
                  keyboardEventSource: source,
                  virtualKey: 0,
                  keyDown: false
              ),
              let submitDown = CGEvent(
                  keyboardEventSource: source,
                  virtualKey: 36,
                  keyDown: true
              ),
              let submitUp = CGEvent(
                  keyboardEventSource: source,
                  virtualKey: 36,
                  keyDown: false
              ) else {
            throw CodexDesktopFollowUpError.keyboardEventUnavailable
        }

        let characters = Array(prompt.utf16)
        characters.withUnsafeBufferPointer { buffer in
            keyDown.keyboardSetUnicodeString(
                stringLength: buffer.count,
                unicodeString: buffer.baseAddress
            )
            keyUp.keyboardSetUnicodeString(
                stringLength: buffer.count,
                unicodeString: buffer.baseAddress
            )
        }
        keyDown.post(tap: .cghidEventTap)
        keyUp.post(tap: .cghidEventTap)
        submitDown.post(tap: .cghidEventTap)
        submitUp.post(tap: .cghidEventTap)
    }
}
