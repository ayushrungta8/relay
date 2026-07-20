import Foundation
import Observation
import RelayVoice

enum RelayUpdateCadence: String, CaseIterable, Codable, Identifiable {
    case daily
    case weekly

    var id: Self { self }

    var interval: TimeInterval {
        switch self {
        case .daily: 86_400
        case .weekly: 604_800
        }
    }

    var title: String {
        switch self {
        case .daily: "Daily"
        case .weekly: "Weekly"
        }
    }
}

enum RelaySettingsChange: Equatable {
    case showAtLaunch(Bool)
    case automaticPeeks(Bool)
    case followsPointerAcrossDisplays(Bool)
    case speaksVoiceResponses(Bool)
    case speechVoiceIdentifier(String?)
    case shortcut(RelayGlobalShortcut)
    case automaticallyChecksForUpdates(Bool)
    case updateCadence(RelayUpdateCadence)
    case autoApplyResetCredits(Bool)
    case controllerModel(RelayControllerModel)
    case controllerReasoningEffort(RelayControllerReasoningEffort)
    case restoredDefaults
}

@MainActor
@Observable
final class RelaySettingsStore {
    private enum Key {
        static let showAtLaunch = "relay.settings.showAtLaunch"
        static let automaticPeeks = "relay.settings.automaticPeeks"
        static let followsPointer =
            "relay.settings.followsPointerAcrossDisplays"
        static let speaksVoiceResponses =
            "relay.settings.speaksVoiceResponses"
        static let speechVoiceIdentifier =
            "relay.settings.speechVoiceIdentifier"
        static let shortcut = "relay.settings.pushToTalkShortcut"
        static let automaticallyChecksForUpdates =
            "relay.settings.automaticallyChecksForUpdates"
        static let updateCadence = "relay.settings.updateCadence"
        static let autoApplyResetCredits =
            "relay.autoApplyResetCreditBeforeExpiry"
        static let controllerModel = "relay.settings.controllerModel"
        static let controllerReasoningEffort =
            "relay.settings.controllerReasoningEffort"
    }

    private static let registeredDefaults: [String: Any] = [
        Key.showAtLaunch: true,
        Key.automaticPeeks: true,
        Key.followsPointer: true,
        Key.speaksVoiceResponses: true,
        Key.automaticallyChecksForUpdates: true,
        Key.updateCadence: RelayUpdateCadence.daily.rawValue,
        Key.autoApplyResetCredits: false,
        Key.controllerModel: RelayControllerModel.luna.rawValue,
        Key.controllerReasoningEffort:
            RelayControllerReasoningEffort.medium.rawValue,
    ]

    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private var suppressNotifications = false
    @ObservationIgnored var onChange: ((RelaySettingsChange) -> Void)?

    var showAtLaunch: Bool {
        didSet {
            persist(showAtLaunch, key: Key.showAtLaunch)
            notify(.showAtLaunch(showAtLaunch), oldValue != showAtLaunch)
        }
    }

    var automaticPeeks: Bool {
        didSet {
            persist(automaticPeeks, key: Key.automaticPeeks)
            notify(.automaticPeeks(automaticPeeks), oldValue != automaticPeeks)
        }
    }

    var followsPointerAcrossDisplays: Bool {
        didSet {
            persist(followsPointerAcrossDisplays, key: Key.followsPointer)
            notify(
                .followsPointerAcrossDisplays(followsPointerAcrossDisplays),
                oldValue != followsPointerAcrossDisplays
            )
        }
    }

    var speaksVoiceResponses: Bool {
        didSet {
            persist(speaksVoiceResponses, key: Key.speaksVoiceResponses)
            notify(
                .speaksVoiceResponses(speaksVoiceResponses),
                oldValue != speaksVoiceResponses
            )
        }
    }

    var speechVoiceIdentifier: String? {
        didSet {
            if let speechVoiceIdentifier {
                defaults.set(
                    speechVoiceIdentifier,
                    forKey: Key.speechVoiceIdentifier
                )
            } else {
                defaults.removeObject(forKey: Key.speechVoiceIdentifier)
            }
            notify(
                .speechVoiceIdentifier(speechVoiceIdentifier),
                oldValue != speechVoiceIdentifier
            )
        }
    }

    var shortcut: RelayGlobalShortcut {
        didSet {
            if let data = try? JSONEncoder().encode(shortcut) {
                defaults.set(data, forKey: Key.shortcut)
            }
            notify(.shortcut(shortcut), oldValue != shortcut)
        }
    }

    var automaticallyChecksForUpdates: Bool {
        didSet {
            persist(
                automaticallyChecksForUpdates,
                key: Key.automaticallyChecksForUpdates
            )
            notify(
                .automaticallyChecksForUpdates(
                    automaticallyChecksForUpdates
                ),
                oldValue != automaticallyChecksForUpdates
            )
        }
    }

    var updateCadence: RelayUpdateCadence {
        didSet {
            defaults.set(updateCadence.rawValue, forKey: Key.updateCadence)
            notify(
                .updateCadence(updateCadence),
                oldValue != updateCadence
            )
        }
    }

    var autoApplyResetCredits: Bool {
        didSet {
            persist(
                autoApplyResetCredits,
                key: Key.autoApplyResetCredits
            )
            notify(
                .autoApplyResetCredits(autoApplyResetCredits),
                oldValue != autoApplyResetCredits
            )
        }
    }

    var controllerModel: RelayControllerModel {
        didSet {
            defaults.set(controllerModel.rawValue, forKey: Key.controllerModel)
            notify(
                .controllerModel(controllerModel),
                oldValue != controllerModel
            )
            if !controllerModel.supportedReasoningEfforts.contains(
                controllerReasoningEffort
            ) {
                controllerReasoningEffort =
                    controllerModel.defaultReasoningEffort
            }
        }
    }

    var controllerReasoningEffort: RelayControllerReasoningEffort {
        didSet {
            defaults.set(
                controllerReasoningEffort.rawValue,
                forKey: Key.controllerReasoningEffort
            )
            notify(
                .controllerReasoningEffort(controllerReasoningEffort),
                oldValue != controllerReasoningEffort
            )
        }
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        defaults.register(defaults: Self.registeredDefaults)
        showAtLaunch = defaults.bool(forKey: Key.showAtLaunch)
        automaticPeeks = defaults.bool(forKey: Key.automaticPeeks)
        followsPointerAcrossDisplays = defaults.bool(
            forKey: Key.followsPointer
        )
        speaksVoiceResponses = defaults.bool(
            forKey: Key.speaksVoiceResponses
        )
        speechVoiceIdentifier = defaults.string(
            forKey: Key.speechVoiceIdentifier
        )
        shortcut = Self.decodeShortcut(defaults: defaults)
        automaticallyChecksForUpdates = defaults.bool(
            forKey: Key.automaticallyChecksForUpdates
        )
        updateCadence = RelayUpdateCadence(
            rawValue: defaults.string(forKey: Key.updateCadence) ?? ""
        ) ?? .daily
        autoApplyResetCredits = defaults.bool(
            forKey: Key.autoApplyResetCredits
        )
        let selectedModel = RelayControllerModel(
            rawValue: defaults.string(forKey: Key.controllerModel) ?? ""
        ) ?? .luna
        controllerModel = selectedModel
        let storedEffort = RelayControllerReasoningEffort(
            rawValue: defaults.string(
                forKey: Key.controllerReasoningEffort
            ) ?? ""
        ) ?? .medium
        controllerReasoningEffort = selectedModel.supportedReasoningEfforts
            .contains(storedEffort)
            ? storedEffort
            : selectedModel.defaultReasoningEffort
    }

    func restoreDefaults() {
        showAtLaunch = true
        automaticPeeks = true
        followsPointerAcrossDisplays = true
        speaksVoiceResponses = true
        speechVoiceIdentifier = nil
        shortcut = .optionSpace
        automaticallyChecksForUpdates = true
        updateCadence = .daily
        autoApplyResetCredits = false
        controllerModel = .luna
        controllerReasoningEffort = .medium
        onChange?(.restoredDefaults)
    }

    func restoreShortcutWithoutNotifying(_ value: RelayGlobalShortcut) {
        suppressNotifications = true
        shortcut = value
        suppressNotifications = false
    }

    private func persist(_ value: Bool, key: String) {
        defaults.set(value, forKey: key)
    }

    private func notify(_ change: RelaySettingsChange, _ changed: Bool) {
        guard changed, !suppressNotifications else { return }
        onChange?(change)
    }

    private static func decodeShortcut(
        defaults: UserDefaults
    ) -> RelayGlobalShortcut {
        guard
            let data = defaults.data(forKey: Key.shortcut),
            let shortcut = try? JSONDecoder().decode(
                RelayGlobalShortcut.self,
                from: data
            )
        else {
            return .optionSpace
        }
        return shortcut
    }
}
