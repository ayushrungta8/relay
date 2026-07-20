import Foundation

nonisolated final class RelayAttentionDismissalStore: @unchecked Sendable {
    private struct Entry: Codable, Hashable {
        let threadID: String
        let turnID: String
        let dismissedAt: Date

        static func == (lhs: Entry, rhs: Entry) -> Bool {
            lhs.threadID == rhs.threadID && lhs.turnID == rhs.turnID
        }

        func hash(into hasher: inout Hasher) {
            hasher.combine(threadID)
            hasher.combine(turnID)
        }
    }

    private static let key = "relay.attention.dismissedTurns.v1"
    private static let limit = 200

    private let defaults: UserDefaults
    private let lock = NSLock()
    private var entries: [Entry]

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        entries = Self.load(from: defaults)
    }

    static func inMemory() -> RelayAttentionDismissalStore {
        let suite = "RelayAttentionDismissalStore.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite) ?? .standard
        defaults.removePersistentDomain(forName: suite)
        return RelayAttentionDismissalStore(defaults: defaults)
    }

    func contains(threadID: String, turnID: String) -> Bool {
        lock.withLock {
            entries.contains {
                $0.threadID == threadID && $0.turnID == turnID
            }
        }
    }

    func dismiss(
        threadID: String,
        turnID: String,
        at date: Date = .now
    ) {
        lock.withLock {
            entries = entries.filter {
                $0.threadID != threadID || $0.turnID != turnID
            }
            entries.append(
                Entry(
                    threadID: threadID,
                    turnID: turnID,
                    dismissedAt: date
                )
            )
            entries.sort { $0.dismissedAt > $1.dismissedAt }
            entries = Array(entries.prefix(Self.limit))
            save(entries)
        }
    }

    private static func load(from defaults: UserDefaults) -> [Entry] {
        guard let data = defaults.data(forKey: Self.key),
              let entries = try? JSONDecoder().decode(
                  [Entry].self,
                  from: data
              ) else { return [] }
        return entries
    }

    private func save(_ entries: [Entry]) {
        guard let data = try? JSONEncoder().encode(entries) else { return }
        defaults.set(data, forKey: Self.key)
    }
}
