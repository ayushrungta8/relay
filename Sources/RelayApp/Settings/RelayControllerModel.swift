import Foundation

enum RelayControllerModel: String, CaseIterable, Codable, Identifiable {
    case sol = "gpt-5.6-sol"
    case terra = "gpt-5.6-terra"
    case luna = "gpt-5.6-luna"
    case gpt55 = "gpt-5.5"
    case spark = "gpt-5.3-codex-spark"

    var id: Self { self }

    var title: String {
        switch self {
        case .sol: "GPT-5.6-Sol"
        case .terra: "GPT-5.6-Terra"
        case .luna: "GPT-5.6-Luna"
        case .gpt55: "GPT-5.5"
        case .spark: "GPT-5.3-Codex-Spark"
        }
    }

    var detail: String {
        switch self {
        case .sol: "Latest frontier agentic coding model."
        case .terra: "Balanced agentic coding model for everyday work."
        case .luna: "Fast and affordable agentic coding model."
        case .gpt55: "Frontier model for complex coding and research."
        case .spark: "Ultra-fast coding model."
        }
    }

    var supportedReasoningEfforts: [RelayControllerReasoningEffort] {
        switch self {
        case .sol, .terra:
            RelayControllerReasoningEffort.allCases
        case .luna:
            [.low, .medium, .high, .xhigh, .max]
        case .gpt55, .spark:
            [.low, .medium, .high, .xhigh]
        }
    }

    var defaultReasoningEffort: RelayControllerReasoningEffort {
        switch self {
        case .sol: .low
        case .terra, .luna, .gpt55: .medium
        case .spark: .high
        }
    }
}
