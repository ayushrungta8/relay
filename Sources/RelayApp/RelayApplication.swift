import SwiftUI

@main
struct RelayApplication: App {
    @State private var model: RelayAppModel
    private let panelController: RelayNotchPanelController

    init() {
        let model = RelayAppModel()
        _model = State(initialValue: model)
        panelController = RelayNotchPanelController(model: model)
        Task { @MainActor in
            await model.start()
            await model.refresh()
        }
    }

    var body: some Scene {
        MenuBarExtra {
            RelayMenuView(openRelay: openRelay)
        } label: {
            Label("Relay", systemImage: "arrow.left.arrow.right")
                .accessibilityLabel(
                    RelayAccessibilityContract.menuBarLabel
                )
        }
    }

    private func openRelay() {
        panelController.present(.expanded)
    }
}
