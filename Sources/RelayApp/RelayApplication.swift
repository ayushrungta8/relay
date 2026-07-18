import SwiftUI

@main
struct RelayApplication: App {
    @NSApplicationDelegateAdaptor(RelayApplicationDelegate.self)
    private var applicationDelegate

    var body: some Scene {
        Settings {
            EmptyView()
        }
        .commands {
            CommandGroup(after: .appInfo) {
                Button(
                    "Check for Updates…",
                    action: RelayUpdateController.shared.checkForUpdates
                )
            }
        }
    }
}
