import RelayCore

public protocol CodexThreadProviding: Sendable {
    func loadThreads(limit: Int) async throws -> [CodexThread]
}

extension CodexAppServerClient: CodexThreadProviding {}
