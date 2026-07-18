import RelayBrain
import RelayCore

public struct RelayControllerSupervisionAdapter:
    RelaySupervisionStateReading
{
    public typealias PendingInteractions = @Sendable () async ->
        [RelayPendingInteraction]

    private let base: any RelaySupervisionStateReading
    private let pendingInteractions: PendingInteractions

    public init(
        base: any RelaySupervisionStateReading,
        pendingInteractions: @escaping PendingInteractions
    ) {
        self.base = base
        self.pendingInteractions = pendingInteractions
    }

    public func visibleTasks() async -> [RelayTaskSummary]? {
        await base.visibleTasks()
    }

    public func attentionInbox() async -> [RelayTaskSummary] {
        let tasks = await base.attentionInbox()
        let interactions = await pendingInteractions()
        return tasks.map { task in
            let requests = interactions
                .filter { $0.threadID == task.id }
                .flatMap(Self.requests(for:))
            return RelayTaskSummary(
                id: task.id,
                title: task.title,
                project: task.project,
                status: task.status,
                updatedAt: task.updatedAt,
                latestUpdate: task.latestUpdate,
                pendingRequests: requests
            )
        }
    }

    public func currentUsage() async -> RelayControllerUsage? {
        await base.currentUsage()
    }

    public func taskReferenceContext() async -> RelayTaskReferenceContext {
        await base.taskReferenceContext()
    }

    private static func requests(
        for interaction: RelayPendingInteraction
    ) -> [RelayPendingRequestSummary] {
        switch interaction.kind {
        case let .questions(questions):
            questions.map {
                RelayPendingRequestSummary(
                    kind: "question",
                    prompt: $0.question
                )
            }
        case let .approval(approval):
            [
                RelayPendingRequestSummary(
                    kind: "approval",
                    prompt: [approval.title, approval.detail]
                        .compactMap { $0 }
                        .joined(separator: " — ")
                ),
            ]
        }
    }
}
