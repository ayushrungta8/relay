import Foundation

public enum CodexDeepLink {
    public static func thread(id: String) -> URL? {
        guard !id.isEmpty else { return nil }

        var components = URLComponents()
        components.scheme = "codex"
        components.host = "threads"
        components.path = "/\(id)"
        return components.url
    }
}
