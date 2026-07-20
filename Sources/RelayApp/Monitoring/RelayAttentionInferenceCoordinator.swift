import RelayCore

nonisolated struct RelayAttentionCandidate: Sendable, Equatable, Hashable {
    let threadID: String
    let response: RelayTaskFinalResponse
}

nonisolated struct RelayAttentionPreparation: Sendable {
    let tasks: [RelayTaskActivity]
    let candidates: [RelayAttentionCandidate]
}

nonisolated struct RelayInferredAttentionUpdate: Sendable, Equatable {
    let threadID: String
    let turnID: String
    let needsReply: Bool
}

actor RelayAttentionInferenceCoordinator {
    private struct Key: Sendable, Hashable {
        let threadID: String
        let turnID: String
        let fingerprint: String

        init(candidate: RelayAttentionCandidate) {
            threadID = candidate.threadID
            turnID = candidate.response.turnID
            fingerprint = candidate.response.fingerprint
        }
    }

    private let aiClassifier: any RelayAttentionAIClassifying
    private let dismissalStore: RelayAttentionDismissalStore
    private var cachedResults: [Key: Bool] = [:]
    private var cacheOrder: [Key] = []
    private var inFlight: Set<Key> = []

    init(
        aiClassifier: any RelayAttentionAIClassifying,
        dismissalStore: RelayAttentionDismissalStore = .init()
    ) {
        self.aiClassifier = aiClassifier
        self.dismissalStore = dismissalStore
    }

    func prepare(tasks: [RelayTaskActivity]) -> RelayAttentionPreparation {
        var candidates: [RelayAttentionCandidate] = []
        let tasks = tasks.map { task -> RelayTaskActivity in
            guard task.attentionReason != .structuredInteraction,
                  let response = task.latestFinalResponse else {
                return task.settingInferredReplyRequest(false)
            }
            if dismissalStore.contains(
                threadID: task.id,
                turnID: response.turnID
            ) {
                return task.settingInferredReplyRequest(false)
            }

            let candidate = RelayAttentionCandidate(
                threadID: task.id,
                response: response
            )
            let key = Key(candidate: candidate)
            switch RelayConversationalAttentionRules.classify(response.text) {
            case .needsReply:
                cache(true, for: key)
                return task.settingInferredReplyRequest(true)
            case .doesNotNeedReply:
                cache(false, for: key)
                return task.settingInferredReplyRequest(false)
            case .ambiguous:
                if let cached = cachedResults[key] {
                    return task.settingInferredReplyRequest(cached)
                }
                if inFlight.insert(key).inserted {
                    candidates.append(candidate)
                }
                return task.settingInferredReplyRequest(false)
            }
        }
        return RelayAttentionPreparation(tasks: tasks, candidates: candidates)
    }

    func classify(
        _ candidate: RelayAttentionCandidate
    ) async -> RelayInferredAttentionUpdate {
        let key = Key(candidate: candidate)
        let needsReply: Bool
        do {
            needsReply = try await aiClassifier.classify(
                candidate.response.text
            ).needsReply
        } catch {
            needsReply = false
        }
        cache(needsReply, for: key)
        inFlight.remove(key)
        return RelayInferredAttentionUpdate(
            threadID: candidate.threadID,
            turnID: candidate.response.turnID,
            needsReply: needsReply
        )
    }

    func dismiss(task: RelayTaskActivity) {
        guard let response = task.latestFinalResponse else { return }
        dismissalStore.dismiss(
            threadID: task.id,
            turnID: response.turnID
        )
        cache(false, for: Key(candidate: RelayAttentionCandidate(
            threadID: task.id,
            response: response
        )))
    }

    private func cache(_ result: Bool, for key: Key) {
        cacheOrder.removeAll { $0 == key }
        cacheOrder.append(key)
        cachedResults[key] = result
        if cacheOrder.count > 500 {
            let expired = cacheOrder.removeFirst()
            cachedResults[expired] = nil
        }
    }
}
