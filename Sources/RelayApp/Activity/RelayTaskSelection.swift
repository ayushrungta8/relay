import RelayCore

enum RelayTaskSelection {
    static func resolvedID(
        preferredID: String?,
        orderedTasks: [RelayTaskActivity]
    ) -> String? {
        if let preferredID,
           orderedTasks.contains(where: { $0.id == preferredID }) {
            return preferredID
        }
        return orderedTasks.first?.id
    }
}
