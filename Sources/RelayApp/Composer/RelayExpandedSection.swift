enum RelayExpandedSection: String, CaseIterable, Identifiable {
    case activity = "Activity"
    case chat = "Chat"

    var id: Self { self }
}
