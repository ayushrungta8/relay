import Foundation
import Observation
import Sparkle

enum RelayUpdatePresentation: Equatable {
    case idle
    case checking
    case available(version: String)
    case downloading(version: String, progress: Double?)
    case preparing(version: String)
    case upToDate
    case failed(message: String)

    var isVisible: Bool { self != .idle }
}

@MainActor
@Observable
final class RelayUpdateController {
    static let shared = RelayUpdateController()

    private(set) var presentation = RelayUpdatePresentation.idle

    private let userDriver: RelayUpdateUserDriver
    private let updater: SPUUpdater
    private var updateChoice: ((SPUUserUpdateChoice) -> Void)?
    private var offeredVersion: String?
    private var hideStatusTask: Task<Void, Never>?
    private weak var settings: RelaySettingsStore?

    var installedVersion: String {
        Bundle.main.object(
            forInfoDictionaryKey: "CFBundleShortVersionString"
        ) as? String ?? "Unknown"
    }

    private init() {
        let userDriver = RelayUpdateUserDriver()
        self.userDriver = userDriver
        updater = SPUUpdater(
            hostBundle: .main,
            applicationBundle: .main,
            userDriver: userDriver,
            delegate: nil
        )
        userDriver.owner = self

        do {
            try updater.start()
        } catch {
            presentation = .failed(message: error.localizedDescription)
        }
    }

    func checkForUpdates() {
        hideStatusTask?.cancel()
        guard updateChoice == nil, !updater.sessionInProgress else { return }
        presentation = .checking
        updater.checkForUpdates()
    }

    func configure(settings: RelaySettingsStore) {
        self.settings = settings
        synchronizeScheduler(with: settings)
    }

    func applySettingsChange(_ change: RelaySettingsChange) {
        switch change {
        case .automaticallyChecksForUpdates, .updateCadence,
             .restoredDefaults:
            guard let settings else { return }
            synchronizeScheduler(with: settings)
        case .showAtLaunch,
             .automaticPeeks,
             .followsPointerAcrossDisplays,
             .speaksVoiceResponses,
             .speechVoiceIdentifier,
             .shortcut,
             .autoApplyResetCredits,
             .controllerModel,
             .controllerReasoningEffort:
            break
        }
    }

    func installAvailableUpdate() {
        guard let updateChoice else { return }
        self.updateChoice = nil
        presentation = .downloading(
            version: offeredVersion ?? "Update",
            progress: nil
        )
        updateChoice(.install)
    }

    func deferAvailableUpdate() {
        guard let updateChoice else {
            presentation = .idle
            return
        }
        self.updateChoice = nil
        offeredVersion = nil
        presentation = .idle
        updateChoice(.dismiss)
    }

    func dismissStatus() {
        guard updateChoice == nil else { return }
        hideStatusTask?.cancel()
        presentation = .idle
    }

    fileprivate func grantUpdatePermission(
        reply: @escaping (SUUpdatePermissionResponse) -> Void
    ) {
        reply(
            SUUpdatePermissionResponse(
                automaticUpdateChecks:
                    settings?.automaticallyChecksForUpdates ?? true,
                sendSystemProfile: false
            )
        )
    }

    fileprivate func beganUserInitiatedCheck() {
        hideStatusTask?.cancel()
        presentation = .checking
    }

    fileprivate func found(
        item: SUAppcastItem,
        reply: @escaping (SPUUserUpdateChoice) -> Void
    ) {
        guard !item.isInformationOnlyUpdate else {
            reply(.dismiss)
            return
        }

        let version = item.displayVersionString
        offeredVersion = version
        updateChoice = reply
        presentation = .available(version: version)
    }

    fileprivate func updateNotFound(
        acknowledgement: @escaping () -> Void
    ) {
        updateChoice = nil
        offeredVersion = nil
        presentation = .upToDate
        acknowledgement()
        hideStatus(after: .seconds(4))
    }

    fileprivate func failed(
        _ error: any Error,
        acknowledgement: @escaping () -> Void
    ) {
        updateChoice = nil
        offeredVersion = nil
        presentation = .failed(message: error.localizedDescription)
        acknowledgement()
    }

    fileprivate func beganDownload() {
        presentation = .downloading(
            version: offeredVersion ?? "Update",
            progress: nil
        )
    }

    fileprivate func receivedDownloadLength(_ length: UInt64) {
        userDriver.expectedDownloadLength = length
        userDriver.receivedDownloadLength = 0
    }

    fileprivate func receivedDownloadData(_ length: UInt64) {
        userDriver.receivedDownloadLength += length
        let expected = max(
            userDriver.expectedDownloadLength,
            userDriver.receivedDownloadLength
        )
        guard expected > 0 else { return }
        presentation = .downloading(
            version: offeredVersion ?? "Update",
            progress: Double(userDriver.receivedDownloadLength)
                / Double(expected)
        )
    }

    fileprivate func beganPreparing() {
        presentation = .preparing(version: offeredVersion ?? "Update")
    }

    fileprivate func installWhenReady(
        reply: @escaping (SPUUserUpdateChoice) -> Void
    ) {
        presentation = .preparing(version: offeredVersion ?? "Update")
        reply(.install)
    }

    fileprivate func finishedInstallation(
        acknowledgement: @escaping () -> Void
    ) {
        acknowledgement()
    }

    fileprivate func updaterDismissed() {
        updateChoice = nil
        offeredVersion = nil
    }

    private func hideStatus(after duration: Duration) {
        hideStatusTask?.cancel()
        hideStatusTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: duration)
            guard !Task.isCancelled else { return }
            self?.presentation = .idle
        }
    }

    private func synchronizeScheduler(with settings: RelaySettingsStore) {
        updater.automaticallyChecksForUpdates =
            settings.automaticallyChecksForUpdates
        updater.updateCheckInterval = settings.updateCadence.interval
    }
}

@MainActor
private final class RelayUpdateUserDriver: NSObject, SPUUserDriver {
    weak var owner: RelayUpdateController?
    var expectedDownloadLength: UInt64 = 0
    var receivedDownloadLength: UInt64 = 0

    func show(
        _ request: SPUUpdatePermissionRequest,
        reply: @escaping (SUUpdatePermissionResponse) -> Void
    ) {
        owner?.grantUpdatePermission(reply: reply)
    }

    func showUserInitiatedUpdateCheck(
        cancellation: @escaping () -> Void
    ) {
        owner?.beganUserInitiatedCheck()
    }

    func showUpdateFound(
        with appcastItem: SUAppcastItem,
        state: SPUUserUpdateState,
        reply: @escaping (SPUUserUpdateChoice) -> Void
    ) {
        owner?.found(item: appcastItem, reply: reply)
    }

    func showUpdateReleaseNotes(with downloadData: SPUDownloadData) {}

    func showUpdateReleaseNotesFailedToDownloadWithError(
        _ error: any Error
    ) {}

    func showUpdateNotFoundWithError(
        _ error: any Error,
        acknowledgement: @escaping () -> Void
    ) {
        owner?.updateNotFound(acknowledgement: acknowledgement)
    }

    func showUpdaterError(
        _ error: any Error,
        acknowledgement: @escaping () -> Void
    ) {
        owner?.failed(error, acknowledgement: acknowledgement)
    }

    func showDownloadInitiated(cancellation: @escaping () -> Void) {
        owner?.beganDownload()
    }

    func showDownloadDidReceiveExpectedContentLength(_ expectedContentLength: UInt64) {
        owner?.receivedDownloadLength(expectedContentLength)
    }

    func showDownloadDidReceiveData(ofLength length: UInt64) {
        owner?.receivedDownloadData(length)
    }

    func showDownloadDidStartExtractingUpdate() {
        owner?.beganPreparing()
    }

    func showExtractionReceivedProgress(_ progress: Double) {
        owner?.beganPreparing()
    }

    func showReady(
        toInstallAndRelaunch reply: @escaping (SPUUserUpdateChoice) -> Void
    ) {
        owner?.installWhenReady(reply: reply)
    }

    func showInstallingUpdate(
        withApplicationTerminated applicationTerminated: Bool,
        retryTerminatingApplication: @escaping () -> Void
    ) {
        owner?.beganPreparing()
    }

    func showUpdateInstalledAndRelaunched(
        _ relaunched: Bool,
        acknowledgement: @escaping () -> Void
    ) {
        owner?.finishedInstallation(acknowledgement: acknowledgement)
    }

    func dismissUpdateInstallation() {
        owner?.updaterDismissed()
    }

    func showUpdateInFocus() {}
}
