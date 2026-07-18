import AppKit

@MainActor
final class RelayApplicationDelegate: NSObject, NSApplicationDelegate {
    private var model: RelayAppModel?
    private var panelController: RelayNotchPanelController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApplication.shared.setActivationPolicy(
            RelayApplicationPresentation.activationPolicy
        )

        _ = RelayUpdateController.shared

        let model = RelayAppModel()
        let panelController = RelayNotchPanelController(model: model)
        self.model = model
        self.panelController = panelController

        panelController.presentDefaultCompact()
        Task { @MainActor in
            await model.start()
        }
    }
}
