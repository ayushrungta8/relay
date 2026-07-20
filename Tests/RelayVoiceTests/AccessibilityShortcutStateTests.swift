import Testing
@testable import RelayVoice

struct AccessibilityShortcutStateTests {
    @Test
    func matchingPressAndReleaseProducesOneCycle() {
        var state = RelayShortcutEventState(shortcut: .optionSpace)

        #expect(
            state.handle(
                .keyDown(
                    keyCode: 49,
                    modifiers: [.option],
                    isRepeat: false
                )
            ) == .pressed
        )
        #expect(
            state.handle(
                .keyDown(
                    keyCode: 49,
                    modifiers: [.option],
                    isRepeat: true
                )
            ) == nil
        )
        #expect(state.handle(.keyUp(keyCode: 49)) == .released)
    }

    @Test
    func releasingAModifierEndsAnActiveShortcut() {
        var state = RelayShortcutEventState(shortcut: .optionSpace)

        _ = state.handle(
            .keyDown(
                keyCode: 49,
                modifiers: [.option],
                isRepeat: false
            )
        )

        #expect(
            state.handle(.modifiersChanged([])) == .released
        )
        #expect(state.handle(.keyUp(keyCode: 49)) == nil)
    }

    @Test
    func unrelatedOrExtraModifiersDoNotTriggerTheShortcut() {
        var state = RelayShortcutEventState(shortcut: .optionSpace)

        #expect(
            state.handle(
                .keyDown(
                    keyCode: 40,
                    modifiers: [.option],
                    isRepeat: false
                )
            ) == nil
        )
        #expect(
            state.handle(
                .keyDown(
                    keyCode: 49,
                    modifiers: [.option, .shift],
                    isRepeat: false
                )
            ) == nil
        )
    }

    @Test
    func modifierOnlyShortcutUsesFlagsChangedForPressAndRelease() {
        let shortcut = RelayGlobalShortcut(
            keyCode: nil,
            modifiers: [.function, .control, .option]
        )
        var state = RelayShortcutEventState(shortcut: shortcut)

        #expect(state.handle(.modifiersChanged([.control])) == nil)
        #expect(
            state.handle(
                .modifiersChanged([.function, .control, .option])
            ) == .pressed
        )
        #expect(
            state.handle(.modifiersChanged([.control, .option]))
                == .released
        )
    }
}
