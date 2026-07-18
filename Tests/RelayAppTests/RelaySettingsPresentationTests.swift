import RelayVoice
import Testing
@testable import RelayApp

struct RelaySettingsPresentationTests {
    @Test
    func expandedSectionsIncludeSettingsAfterUsage() {
        #expect(
            RelayExpandedSection.allCases
                == [.activity, .chat, .usage, .settings]
        )
    }

    @Test
    func shortcutCopyUsesMacModifierGlyphs() {
        #expect(
            RelayShortcutPresentation.copy(for: .optionSpace)
                == "⌥Space"
        )
        #expect(
            RelayShortcutPresentation.copy(
                for: RelayGlobalShortcut(
                    keyCode: 11,
                    modifiers: [.command, .shift]
                )
            ) == "⇧⌘B"
        )
    }

    @Test
    func invalidShortcutRequiresAModifierAndAKey() {
        #expect(
            !RelayShortcutPresentation.isValid(
                keyCode: 49,
                modifiers: []
            )
        )
        #expect(
            RelayShortcutPresentation.isValid(
                keyCode: 49,
                modifiers: [.option]
            )
        )
    }
}
