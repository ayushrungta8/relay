import Foundation

enum RelayControllerReasoningEffort: String, CaseIterable, Codable, Identifiable {
    case low
    case medium
    case high
    case xhigh
    case max
    case ultra

    var id: Self { self }

    var title: String {
        switch self {
        case .low: "Low"
        case .medium: "Medium"
        case .high: "High"
        case .xhigh: "Extra High"
        case .max: "Max"
        case .ultra: "Ultra"
        }
    }
}
