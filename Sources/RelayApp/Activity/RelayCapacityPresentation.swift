import Foundation
import RelayCore

struct RelayCapacityPresentation {
    enum Level: Equatable {
        case standard
        case warning
        case critical

        init(usedPercent: Int) {
            if usedPercent >= 90 {
                self = .critical
            } else if usedPercent >= 75 {
                self = .warning
            } else {
                self = .standard
            }
        }
    }

    struct Window: Identifiable, Equatable {
        enum Role: String {
            case primary
            case secondary
        }

        let id: Role
        let label: String
        let usedPercent: Int
        let resetDate: Date?
        let level: Level

        var progress: Double {
            Double(min(max(usedPercent, 0), 100)) / 100
        }
    }

    let title: String
    let primary: Window?
    let secondary: Window?
    let resetCreditsCopy: String
    let resetCredits: [RelayRateLimitResetCredit]?

    var windows: [Window] {
        [primary, secondary].compactMap { $0 }
    }

    var availabilityCopy: String {
        windows.isEmpty ? "Usage unavailable" : "Capacity available"
    }

    init(snapshot: RelayUsageSnapshot?) {
        let trimmedName = snapshot?.limitName?.trimmingCharacters(
            in: .whitespacesAndNewlines
        )
        title = if let trimmedName, !trimmedName.isEmpty {
            trimmedName
        } else {
            "Codex capacity"
        }
        primary = Self.window(
            role: .primary,
            value: snapshot?.primary
        )
        secondary = Self.window(
            role: .secondary,
            value: snapshot?.secondary
        )
        resetCredits = snapshot?.resetCredits
        resetCreditsCopy = Self.resetCreditsCopy(
            count: snapshot?.resetCreditsAvailableCount
        )
    }

    static func timestampLabel(
        for date: Date,
        locale: Locale = .current,
        timeZone: TimeZone = .current
    ) -> String {
        date.formatted(
            Date.FormatStyle(
                date: .abbreviated,
                time: .shortened,
                locale: locale,
                timeZone: timeZone
            )
        )
    }

    private static func window(
        role: Window.Role,
        value: RelayRateLimitWindow?
    ) -> Window? {
        guard let value else { return nil }
        return Window(
            id: role,
            label: durationLabel(minutes: value.windowDurationMins),
            usedPercent: value.usedPercent,
            resetDate: value.resetsAt.map {
                Date(timeIntervalSince1970: TimeInterval($0))
            },
            level: Level(usedPercent: value.usedPercent)
        )
    }

    private static func durationLabel(minutes: Int64?) -> String {
        guard let minutes, minutes > 0 else {
            return "Window duration unavailable"
        }
        if minutes.isMultiple(of: 1_440) {
            let days = minutes / 1_440
            return "\(days)-day window"
        }
        if minutes.isMultiple(of: 60) {
            let hours = minutes / 60
            return "\(hours)-hour window"
        }
        return "\(minutes)-minute window"
    }

    private static func resetCreditsCopy(count: Int64?) -> String {
        guard let count else { return "Reset credits unavailable" }
        return switch count {
        case 0:
            "No reset credits available"
        case 1:
            "1 reset credit available"
        default:
            "\(count) reset credits available"
        }
    }
}
