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
    public let activeFlags: [CodexThreadActiveFlag]

    public init(
        id: String,
        name: String? = nil,
        preview: String,
        cwd: String,
        updatedAt: Int,
        status: CodexThreadStatus,
        activeFlags: [CodexThreadActiveFlag] = []
    ) {
        self.id = id
        self.name = name
        self.preview = preview
        self.cwd = cwd
        self.updatedAt = updatedAt
        self.status = status
        self.activeFlags = activeFlags
    }

    private enum CodingKeys: String, CodingKey {
        case id
        case name
        case preview
        case cwd
        case updatedAt
        case status
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let status = try container.decode(
            CodexThreadStatusPayload.self,
            forKey: .status
        )
        id = try container.decode(String.self, forKey: .id)
        name = try container.decodeIfPresent(String.self, forKey: .name)
        preview = try container.decode(String.self, forKey: .preview)
        cwd = try container.decode(String.self, forKey: .cwd)
        updatedAt = try container.decode(Int.self, forKey: .updatedAt)
        self.status = status.type
        activeFlags = status.activeFlags
    }
}

public enum CodexThreadActiveFlag: Sendable, Equatable, Hashable, Codable {
    case waitingOnApproval
    case waitingOnUserInput
    case unknown(String)

    public var rawValue: String {
        switch self {
        case .waitingOnApproval:
            "waitingOnApproval"
        case .waitingOnUserInput:
            "waitingOnUserInput"
        case let .unknown(value):
            value
        }
    }

    public init(from decoder: any Decoder) throws {
        let value = try decoder.singleValueContainer().decode(String.self)
        switch value {
        case "waitingOnApproval":
            self = .waitingOnApproval
        case "waitingOnUserInput":
            self = .waitingOnUserInput
        default:
            self = .unknown(value)
        }
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }
}

public enum CodexThreadStatus: String, Sendable, Equatable {
    case active
    case idle
    case notLoaded
    case systemError
    case unknown
}

private struct CodexThreadStatusPayload: Decodable {
    let type: CodexThreadStatus
    let activeFlags: [CodexThreadActiveFlag]

    private enum CodingKeys: String, CodingKey {
        case type
        case activeFlags
    }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        type = try container.decode(
            CodexThreadStatus.self,
            forKey: .type
        )
        activeFlags = try container.decodeIfPresent(
            [CodexThreadActiveFlag].self,
            forKey: .activeFlags
        ) ?? []
    }
}

extension CodexThreadStatus: Decodable {
    private enum CodingKeys: String, CodingKey {
        case type
    }

    public init(from decoder: Decoder) throws {
        if let rawValue = try? decoder.singleValueContainer()
            .decode(String.self) {
            self = CodexThreadStatus(rawValue: rawValue) ?? .unknown
            return
        }
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let rawValue = try container.decode(String.self, forKey: .type)
        self = CodexThreadStatus(rawValue: rawValue) ?? .unknown
    }
}
