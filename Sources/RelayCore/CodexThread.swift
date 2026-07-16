import Foundation

public struct CodexThreadListEnvelope: Decodable, Sendable {
    public let id: Int
    public let result: CodexThreadList
}

public struct CodexThreadList: Decodable, Sendable {
    public let data: [CodexThread]
    public let nextCursor: String?
}

public struct CodexThread: Decodable, Identifiable, Sendable, Equatable {
    public let id: String
    public let name: String?
    public let preview: String
    public let cwd: String
    public let updatedAt: Int
    public let status: CodexThreadStatus

    public init(
        id: String,
        name: String? = nil,
        preview: String,
        cwd: String,
        updatedAt: Int,
        status: CodexThreadStatus
    ) {
        self.id = id
        self.name = name
        self.preview = preview
        self.cwd = cwd
        self.updatedAt = updatedAt
        self.status = status
    }
}

public enum CodexThreadStatus: String, Sendable, Equatable {
    case active
    case idle
    case notLoaded
    case systemError
    case unknown
}

extension CodexThreadStatus: Decodable {
    private enum CodingKeys: String, CodingKey {
        case type
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let rawValue = try container.decode(String.self, forKey: .type)
        self = CodexThreadStatus(rawValue: rawValue) ?? .unknown
    }
}
