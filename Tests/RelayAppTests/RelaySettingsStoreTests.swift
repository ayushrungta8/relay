import Foundation
import RelayVoice
import Testing
@testable import RelayApp

@MainActor
struct RelaySettingsStoreTests {
    @Test
    func registersExplicitDefaults() {
        let settings = RelaySettingsStore(defaults: ephemeralDefaults())

        #expect(settings.showAtLaunch)
        #expect(settings.automaticPeeks)
        #expect(settings.followsPointerAcrossDisplays)
        #expect(settings.speaksVoiceResponses)
        #expect(settings.speechVoiceIdentifier == nil)
        #expect(settings.shortcut == .optionSpace)
        #expect(settings.automaticallyChecksForUpdates)
        #expect(settings.updateCadence == .daily)
        #expect(!settings.autoApplyResetCredits)
    }

    @Test
    func persistsChangesAcrossStoreInstances() {
        let defaults = ephemeralDefaults()
        let settings = RelaySettingsStore(defaults: defaults)
        let shortcut = RelayGlobalShortcut(
            keyCode: nil,
            modifiers: [.function, .control, .option]
        )

        settings.showAtLaunch = false
        settings.automaticPeeks = false
        settings.followsPointerAcrossDisplays = false
        settings.speaksVoiceResponses = false
        settings.speechVoiceIdentifier = "voice.example"
        settings.shortcut = shortcut
        settings.automaticallyChecksForUpdates = false
        settings.updateCadence = .weekly
        settings.autoApplyResetCredits = true

        let restored = RelaySettingsStore(defaults: defaults)
        #expect(!restored.showAtLaunch)
        #expect(!restored.automaticPeeks)
        #expect(!restored.followsPointerAcrossDisplays)
        #expect(!restored.speaksVoiceResponses)
        #expect(restored.speechVoiceIdentifier == "voice.example")
        #expect(restored.shortcut == shortcut)
        #expect(!restored.automaticallyChecksForUpdates)
        #expect(restored.updateCadence == .weekly)
        #expect(restored.autoApplyResetCredits)
    }

    @Test
    func restoreDefaultsUsesNormalChangeNotifications() {
        let settings = RelaySettingsStore(defaults: ephemeralDefaults())
        settings.automaticPeeks = false
        settings.updateCadence = .weekly
        var changes: [RelaySettingsChange] = []
        settings.onChange = { changes.append($0) }

        settings.restoreDefaults()

        #expect(settings.automaticPeeks)
        #expect(settings.updateCadence == .daily)
        #expect(changes.contains(.automaticPeeks(true)))
        #expect(changes.contains(.updateCadence(.daily)))
        #expect(changes.last == .restoredDefaults)
    }

    @Test
    func cadenceMapsToSparkleIntervals() {
        #expect(RelayUpdateCadence.daily.interval == 86_400)
        #expect(RelayUpdateCadence.weekly.interval == 604_800)
    }

    private func ephemeralDefaults() -> UserDefaults {
        let name = "RelaySettingsStoreTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name) ?? .standard
        defaults.removePersistentDomain(forName: name)
        return defaults
    }
}
