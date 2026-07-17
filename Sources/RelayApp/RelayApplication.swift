import SwiftUI

@main
struct RelayApplication: App {
    @NSApplicationDelegateAdaptor(RelayApplicationDelegate.self)
    private var applicationDelegate

    var body: some Scene {
        Settings {
            EmptyView()
        }
    }
}
