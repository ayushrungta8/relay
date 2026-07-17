import Foundation

nonisolated enum RelayConnectionState: Sendable, Equatable {
    case idle
    case connecting
    case connected(lastUpdatedAt: Date)
    case offline(
        message: String,
        reconnectAttempt: Int,
        lastUpdatedAt: Date?
    )

    var isConnected: Bool {
        guard case .connected = self else { return false }
        return true
    }

    var isOffline: Bool {
        guard case .offline = self else { return false }
        return true
    }

    var errorMessage: String? {
        guard case let .offline(message, _, _) = self else { return nil }
        return message
    }

    var lastUpdatedAt: Date? {
        switch self {
        case let .connected(lastUpdatedAt): lastUpdatedAt
        case let .offline(_, _, lastUpdatedAt): lastUpdatedAt
        case .idle, .connecting: nil
        }
    }
}
