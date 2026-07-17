struct RelayOrphanedDraft: Equatable, Identifiable {
    enum Kind: Equatable {
        case pendingAnswer
        case followUp
    }

    let kind: Kind
    let ownerID: String

    var id: String {
        switch kind {
        case .pendingAnswer: "pending:\(ownerID)"
        case .followUp: "follow-up:\(ownerID)"
        }
    }
}
