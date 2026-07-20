import AppKit

@MainActor
final class RelayApplicationDelegate: NSObject, NSApplicationDelegate {
    private let settings = RelaySettingsStore()
    private var model: RelayAppModel?
    private var panelController: RelayNotchPanelController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApplication.shared.setActivationPolicy(
            RelayApplicationPresentation.activationPolicy
        )

        let updateController = RelayUpdateController.shared
        updateController.configure(settings: settings)

        let model = RelayAppModel(settings: settings)
        let panelController = RelayNotchPanelController(
            model: model,
            settings: settings
        )
        self.model = model
        self.panelController = panelController

        settings.onChange = {
            [weak model, weak panelController, weak updateController] change in
            model?.applySettingsChange(change)
            panelController?.applySettingsChange(change)
            updateController?.applySettingsChange(change)
        }

        if settings.showAtLaunch {
            panelController.presentDefaultCompact()
        }
        Task { @MainActor in
            await model.start()
        }
    }

    func applicationShouldHandleReopen(
        _ sender: NSApplication,
        hasVisibleWindows flag: Bool
    ) -> Bool {
        panelController?.present(.expanded)
        return true
    }

    func applicationDidBecomeActive(_ notification: Notification) {
        model?.retryShortcutRegistration()
    }
}
