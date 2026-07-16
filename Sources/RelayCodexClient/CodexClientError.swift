import Foundation

public enum CodexClientError: Error, Sendable {
    case executableNotFound
    case invalidLimit
    case invalidState(String)
    case processLaunchFailed(String)
    case transportClosed
    case timedOut
    case malformedResponse
    case responseDecodingFailed(method: String, reason: String)
    case requestCancelled
    case rpc(code: Int, message: String)
}

extension CodexClientError: LocalizedError {
    public var errorDescription: String? {
        switch self {
        case .executableNotFound:
            "Relay could not find the Codex executable."
        case .invalidLimit:
            "The requested Codex task limit must be positive."
        case let .invalidState(message):
            message
        case let .processLaunchFailed(message):
            "Relay could not launch Codex app-server: \(message)"
        case .transportClosed:
            "Codex app-server closed before answering Relay."
        case .timedOut:
            "Codex app-server took too long to answer Relay."
        case .malformedResponse:
            "Codex app-server returned a response Relay could not read."
        case let .responseDecodingFailed(method, reason):
            "Relay could not decode the \(method) response: \(reason)"
        case .requestCancelled:
            "The Codex app-server request was cancelled."
        case let .rpc(code, message):
            "Codex app-server error \(code): \(message)"
        }
    }
}
