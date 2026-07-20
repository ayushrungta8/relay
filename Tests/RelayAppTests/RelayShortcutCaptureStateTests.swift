import RelayVoice
import Testing
@testable import RelayApp

@MainActor
struct RelayShortcutCaptureStateTests {
    @Test
    func releasingModifierChordCommitsItsPeakCombination() {
        var state = RelayShortcutCaptureState()

        #expect(state.modifiersChanged([.control]) == nil)
        #expect(
            state.modifiersChanged([.function, .control, .option])
                == nil
        )
        #expect(
            state.modifiersChanged([.control, .option])
                == RelayGlobalShortcut(
                    keyCode: nil,
                    modifiers: [.function, .control, .option]
                )
        )
    }

    @Test
    func keyPressCommitsAKeyAndItsModifiers() {
        var state = RelayShortcutCaptureState()

        #expect(
            state.keyDown(
                keyCode: 40,
                modifiers: [.control, .option]
            ) == RelayGlobalShortcut(
                keyCode: 40,
                modifiers: [.control, .option]
            )
        )
    }
}
