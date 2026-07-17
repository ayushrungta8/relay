import RelayCore

struct RelayTaskActions {
    let select: (RelayTaskActivity) async -> Void
    let open: (RelayTaskActivity) async throws -> Void
    let markRead: (RelayTaskActivity) async -> Void
    let send: (RelayTaskActivity, String) async throws -> Void
    let interrupt: (RelayTaskActivity) async throws -> Void
}
