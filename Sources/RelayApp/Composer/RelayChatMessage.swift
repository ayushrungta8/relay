import Foundation

struct RelayChatMessage: Identifiable, Equatable, Sendable {
    enum Role: Equatable, Sendable {
        case user
        case relay
    }

    let id: UUID
    let role: Role
    var text: String

    init(
        id: UUID = UUID(),
        role: Role,
        text: String
    ) {
        self.id = id
        self.role = role
        self.text = text
    }
}
