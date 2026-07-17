enum RelayExpandedSection: String, CaseIterable, Identifiable {
    case activity = "Activity"
    case chat = "Chat"
    case usage = "Usage"

    var id: Self { self }
}
