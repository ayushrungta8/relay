import Foundation
import RelayBrain
import RelayCodexClient
import RelayCore

public enum CodexRelayTaskOperationsError:
    Error,
    Sendable,
    Equatable
{
    case controllerThreadCannotBeManaged
}

extension CodexRelayTaskOperationsError: LocalizedError {
    public var errorDescription: String? {
        switch self {
        case .controllerThreadCannotBeManaged:
            "Relay cannot treat its own controller as a worker task."
        }
    }
}

public actor CodexRelayTaskOperationsAdapter: RelayTaskOperations {
    private let client: CodexTaskOperationsClient
    private let controllerThreadStore:
        (any RelayControllerThreadStoring)?

    public init(
        client: CodexTaskOperationsClient,
        controllerThreadStore:
            (any RelayControllerThreadStoring)? = nil
    ) {
        self.client = client
        self.controllerThreadStore = controllerThreadStore
    }

    public func listTasks() async throws -> [RelayTaskSummary] {
        let controllerID = await controllerThreadStore?.loadThreadID()
        return try await client.listTasks(limit: .max)
            .filter {
                !Self.isControllerThread(
                    $0,
                    controllerID: controllerID
                )
            }
            .map { Self.summary($0) }
    }

    public func getTask(id: String) async throws -> RelayTaskSummary? {
        let controllerID = await controllerThreadStore?.loadThreadID()
        guard id != controllerID else { return nil }

        let runtime = try await client.getTask(id: id)
        guard !Self.isControllerThread(
            runtime.thread,
            controllerID: controllerID
        ) else {
            return nil
        }
        return Self.summary(
            runtime.thread,
            latestUpdate: runtime.latestUpdate
        )
    }

    public func startTask(
        prompt: String,
        cwd: String?
    ) async throws -> RelayTaskSummary {
        let launch = try await client.startTask(
            prompt: prompt,
            cwd: cwd
        )
        return Self.summary(launch.thread)
    }

    public func interruptTask(id: String) async throws {
        try await ensureWorkerThread(id: id)
        try await client.interruptTask(id: id)
    }

    private func ensureWorkerThread(id: String) async throws {
        let controllerID = await controllerThreadStore?.loadThreadID()
        guard id != controllerID else {
            throw CodexRelayTaskOperationsError
                .controllerThreadCannotBeManaged
        }
    }

    private static func isControllerThread(
        _ thread: CodexThread,
        controllerID: String?
    ) -> Bool {
        if thread.id == controllerID {
            return true
        }
        return thread.name?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .caseInsensitiveCompare("Relay Controller") == .orderedSame
    }

    private static func summary(
        _ thread: CodexThread,
        latestUpdate: String? = nil
    ) -> RelayTaskSummary {
        RelayTaskSummary(
            id: thread.id,
            title: thread.displayTitle,
            project: thread.cwd,
            status: thread.status.rawValue,
            updatedAt: Date(
                timeIntervalSince1970: TimeInterval(thread.updatedAt)
            ),
            latestUpdate: latestUpdate
        )
    }
}

private extension CodexThread {
    var displayTitle: String {
        let title = name?.trimmingCharacters(
            in: .whitespacesAndNewlines
        )
        if let title, !title.isEmpty {
            return title
        }

        let preview = preview.trimmingCharacters(
            in: .whitespacesAndNewlines
        )
        return preview.isEmpty ? "Untitled Codex task" : preview
    }
}
