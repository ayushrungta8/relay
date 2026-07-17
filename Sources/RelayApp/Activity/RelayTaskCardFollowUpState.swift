import Foundation

struct RelayTaskCardFollowUpState: Equatable {
    private(set) var allowsTaskManagement = true
    var isComposing = false
    var draft = ""

    var isDirty: Bool {
        !draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    mutating func beginFollowUp(allowsTaskManagement: Bool) {
        synchronize(allowsTaskManagement: allowsTaskManagement)
        guard allowsTaskManagement else { return }
        isComposing = true
    }

    mutating func synchronize(allowsTaskManagement: Bool) {
        self.allowsTaskManagement = allowsTaskManagement
        guard !allowsTaskManagement else { return }
        clear()
    }

    mutating func clear() {
        isComposing = false
        draft = ""
    }
}
