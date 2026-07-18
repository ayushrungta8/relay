enum RelayExpandedSection: String, CaseIterable, Identifiable {
    case activity = "Activity"
    case chat = "Chat"
    case usage = "Usage"
    case settings = "Settings"

    var id: Self { self }

    static func selection(
        preserving current: Self,
        previousChatMessageCount: Int,
        chatMessageCount: Int
    ) -> Self {
        chatMessageCount > previousChatMessageCount ? .chat : current
    }
}
