import Foundation

struct RelayConnectionPresentation: Equatable {
    let label: String
    let detail: String?
    let showsRetry: Bool
    let isVisible: Bool

    init(state: RelayConnectionState, now: Date = .now) {
        switch state {
        case .idle:
            label = "Codex connection idle"
            detail = nil
            showsRetry = true
            isVisible = false
        case .connecting:
            label = "Reconnecting"
            detail = nil
            showsRetry = false
            isVisible = true
        case .connected:
            label = "Connected"
            detail = nil
            showsRetry = false
            isVisible = false
        case let .offline(message, _, lastUpdatedAt):
            if let lastUpdatedAt {
                label = "Reconnecting · snapshot updated \(Self.age(from: lastUpdatedAt, to: now))"
            } else {
                label = "Reconnecting · snapshot unavailable"
            }
            detail = message
            showsRetry = true
            isVisible = true
        }
    }

    private static func age(from date: Date, to now: Date) -> String {
        let seconds = max(0, Int(now.timeIntervalSince(date)))
        if seconds < 60 { return "just now" }
        let minutes = seconds / 60
        if minutes < 60 { return "\(minutes) min ago" }
        let hours = minutes / 60
        if hours < 24 { return "\(hours) hr ago" }
        return "\(hours / 24) d ago"
    }
}
