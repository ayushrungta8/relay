import RelayCore

struct RelayAutomaticPeekTrigger: Equatable, Sendable {
    let threadID: String
    let state: RelayTaskAttentionState
    let updatedAt: Int
    let hasUnreadCompletion: Bool
}
