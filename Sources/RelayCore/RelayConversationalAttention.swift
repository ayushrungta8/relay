import Foundation

public struct RelayTaskFinalResponse: Sendable, Equatable, Hashable {
    public let turnID: String
    public let text: String
    public let fingerprint: String

    public init(turnID: String, text: String, fingerprint: String) {
        self.turnID = turnID
        self.text = text
        self.fingerprint = fingerprint
    }
}

public enum RelayLocalAttentionClassification: Sendable, Equatable {
    case needsReply
    case doesNotNeedReply
    case ambiguous
}

public enum RelayConversationalAttentionAction: Sendable, Equatable {
    case approve

    public var reply: String {
        switch self {
        case .approve:
            "approved"
        }
    }
}

public struct RelayAIAttentionClassification: Sendable, Equatable {
    public let needsReply: Bool
    public let reason: String

    public init(needsReply: Bool, reason: String) {
        self.needsReply = needsReply
        self.reason = reason
    }
}

public protocol RelayAttentionAIClassifying: Sendable {
    func classify(_ text: String) async throws
        -> RelayAIAttentionClassification
}

public enum RelayConversationalAttentionRules {
    private static let approvalRequestPhrases = [
        "reply approved",
        "reply with approved",
        "respond approved",
        "respond with approved",
        "say approved",
        "say \"approved\"",
        "say “approved”",
    ]

    private static let explicitRequestPhrases = [
        "reply approved",
        "reply with approved",
        "please reply",
        "please review",
        "please confirm",
        "confirm before i continue",
        "confirm before i proceed",
        "before i continue",
        "before i proceed",
        "tell me when",
        "let me know when",
        "send me the",
        "provide the",
        "say next",
        "say “next”",
        "say \"next\"",
    ]

    private static let ambiguousMarkers = [
        "?",
        "let me know",
        "would you like",
        "do you want",
        "should i",
        "which option",
        "which approach",
        "please",
        "confirm",
        "reply",
        "approve",
        "choose",
        "tell me",
        "send me",
        "provide",
    ]

    public static func classify(
        _ text: String
    ) -> RelayLocalAttentionClassification {
        let normalized = text
            .lowercased()
            .split(whereSeparator: \Character.isWhitespace)
            .joined(separator: " ")
        guard !normalized.isEmpty else { return .doesNotNeedReply }
        let actionWindow = String(normalized.suffix(1_200))
        if explicitRequestPhrases.contains(where: actionWindow.contains) {
            return .needsReply
        }
        if ambiguousMarkers.contains(where: normalized.contains) {
            return .ambiguous
        }
        return .doesNotNeedReply
    }

    public static func suggestedAction(
        for text: String
    ) -> RelayConversationalAttentionAction? {
        let actionWindow = normalizedActionWindow(text)
        guard approvalRequestPhrases.contains(where: actionWindow.contains)
        else { return nil }
        return .approve
    }

    private static func normalizedActionWindow(_ text: String) -> String {
        let normalized = text
            .lowercased()
            .split(whereSeparator: \Character.isWhitespace)
            .joined(separator: " ")
        return String(normalized.suffix(1_200))
    }
}
