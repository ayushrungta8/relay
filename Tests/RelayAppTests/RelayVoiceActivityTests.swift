import Testing
@testable import RelayApp

@MainActor
struct RelayVoiceActivityTests {
    @Test
    func labelsMatchTheHeaderCopy() {
        #expect(RelayVoiceActivity.inactive.label == "")
        #expect(RelayVoiceActivity.listening.label == "Listening…")
        #expect(RelayVoiceActivity.thinking.label == "Thinking…")
        #expect(RelayVoiceActivity.speaking.label == "Speaking…")
    }

    @Test
    func onlyTheTransientStatesAreActive() {
        #expect(RelayVoiceActivity.inactive.isActive == false)
        #expect(RelayVoiceActivity.listening.isActive)
        #expect(RelayVoiceActivity.thinking.isActive)
        #expect(RelayVoiceActivity.speaking.isActive)
    }

    @Test
    func everyActiveStatePulsesAtItsOwnTempo() {
        #expect(RelayVoiceActivity.listening.pulses)
        #expect(RelayVoiceActivity.thinking.pulses)
        #expect(RelayVoiceActivity.speaking.pulses)
        #expect(RelayVoiceActivity.inactive.pulses == false)

        // Distinct cadences so the states read apart beyond color.
        #expect(RelayVoiceActivity.listening.pulsePeriod == 0.9)
        #expect(RelayVoiceActivity.thinking.pulsePeriod == 1.4)
        #expect(RelayVoiceActivity.speaking.pulsePeriod == 0.65)
        #expect(RelayVoiceActivity.inactive.pulsePeriod == 0)
    }
}
