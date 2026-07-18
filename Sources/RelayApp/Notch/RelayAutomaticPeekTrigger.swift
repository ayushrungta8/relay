import RelayCore

struct RelayAutomaticPeekTrigger: Equatable, Sendable {
    let threadID: String
    let state: RelayTaskAttentionState
    let updatedAt: Int
    let hasUnreadCompletion: Bool
}

enum RelayAutomaticPeekPolicy {
    static func trigger(
        _ candidate: RelayAutomaticPeekTrigger?,
        enabled: Bool
    ) -> RelayAutomaticPeekTrigger? {
        enabled ? candidate : nil
    }
}
