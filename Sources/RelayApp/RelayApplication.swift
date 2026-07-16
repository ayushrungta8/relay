import SwiftUI

@main
struct RelayApplication: App {
    @State private var model: RelayAppModel

    init() {
        let model = RelayAppModel()
        _model = State(initialValue: model)
        Task { @MainActor in
            await model.start()
            await model.refresh()
        }
    }

    var body: some Scene {
        MenuBarExtra {
            RelayMenuView(model: model)
        } label: {
            Label("Relay", systemImage: "arrow.left.arrow.right")
        }
        .menuBarExtraStyle(.window)
    }
}
