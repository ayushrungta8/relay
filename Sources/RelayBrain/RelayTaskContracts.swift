import Foundation

public struct RelayTaskSummary: Sendable, Equatable, Encodable {
    public let id: String
    public let title: String
    public let project: String
    public let status: String
    public let updatedAt: Date
    public let latestUpdate: String?

    public init(
        id: String,
        title: String,
        project: String,
        status: String,
        updatedAt: Date,
        latestUpdate: String? = nil
    ) {
        self.id = id
        self.title = title
        self.project = project
        self.status = status
        self.updatedAt = updatedAt
        self.latestUpdate = latestUpdate
    }
}

public protocol RelayTaskOperations: Sendable {
    func listTasks() async throws -> [RelayTaskSummary]
    func getTask(id: String) async throws -> RelayTaskSummary?
    func startTask(prompt: String, cwd: String) async throws -> RelayTaskSummary
    func sendToTask(id: String, prompt: String) async throws
    func interruptTask(id: String) async throws
}
