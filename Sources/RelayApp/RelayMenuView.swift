import AppKit
import SwiftUI

struct RelayMenuView: View {
    let openRelay: () -> Void

    var body: some View {
        Button(
            RelayAccessibilityContract.MenuAction.openRelay.title,
            systemImage:
                RelayAccessibilityContract.MenuAction.openRelay.systemImage,
            action: openRelay
        )
        .keyboardShortcut(
            RelayAccessibilityContract.openRelayKeyEquivalent,
            modifiers: RelayAccessibilityContract.openRelayModifiers
        )

        Button(
            RelayAccessibilityContract.MenuAction.openCodex.title,
            systemImage:
                RelayAccessibilityContract.MenuAction.openCodex.systemImage,
            action: openCodex
        )

        Divider()

        Button(
            RelayAccessibilityContract.MenuAction.quit.title,
            systemImage:
                RelayAccessibilityContract.MenuAction.quit.systemImage,
            action: quit
        )
        .keyboardShortcut(
            RelayAccessibilityContract.quitKeyEquivalent,
            modifiers: RelayAccessibilityContract.quitModifiers
        )
    }

    private func openCodex() {
        guard let appURL = NSWorkspace.shared.urlForApplication(
            withBundleIdentifier: "com.openai.codex"
        ) else {
            return
        }
        NSWorkspace.shared.open(appURL)
    }

    private func quit() {
        NSApplication.shared.terminate(nil)
    }
}
