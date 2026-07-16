import Foundation
import RelayCore

struct RelayTaskOpenAction {
    enum OpenError: LocalizedError {
        case invalidDeepLink
        case rejected

        var errorDescription: String? {
            switch self {
            case .invalidDeepLink:
                "Relay could not create a link to this Codex task."
            case .rejected:
                "Codex could not open this task."
            }
        }
    }

    let openURL: (URL) -> Bool
    let markRead: (String) async -> Void

    func callAsFunction(_ task: RelayTaskActivity) async throws {
        guard let url = CodexDeepLink.thread(id: task.id) else {
            throw OpenError.invalidDeepLink
        }
        guard openURL(url) else {
            throw OpenError.rejected
        }
        await markRead(task.id)
    }
}
