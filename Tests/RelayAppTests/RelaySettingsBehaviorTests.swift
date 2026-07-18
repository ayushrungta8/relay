import Testing
@testable import RelayApp

@MainActor
struct RelaySettingsBehaviorTests {
    @Test
    func automaticPeekPolicySuppressesTriggersWhenDisabled() {
        let candidate = RelayAutomaticPeekTrigger(
            threadID: "worker",
            state: .needsInput,
            updatedAt: 42,
            hasUnreadCompletion: false
        )

        #expect(
            RelayAutomaticPeekPolicy.trigger(
                candidate,
                enabled: false
            ) == nil
        )
        #expect(
            RelayAutomaticPeekPolicy.trigger(
                candidate,
                enabled: true
            ) == candidate
        )
    }
}
