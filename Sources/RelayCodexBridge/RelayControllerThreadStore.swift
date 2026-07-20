import Foundation
import RelayBrain

public protocol RelayControllerThreadStoring: Sendable {
    func loadThreadID() async -> String?
    func saveThreadID(_ id: String) async
}

public actor RelayControllerThreadFileStore:
    RelayControllerThreadStoring
{
    private let fileURL: URL

    public init(
        fileURL: URL = RelayControllerThreadFileStore.defaultFileURL
    ) {
        self.fileURL = fileURL
    }

    public func loadThreadID() -> String? {
        guard
            let data = try? Data(contentsOf: fileURL),
            let value = String(data: data, encoding: .utf8)?
                .trimmingCharacters(in: .whitespacesAndNewlines),
            !value.isEmpty
        else {
            return nil
        }
        return value
    }

    public func saveThreadID(_ id: String) {
        let value = id.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty, let data = value.data(using: .utf8) else {
            return
        }

        let directory = fileURL.deletingLastPathComponent()
        do {
            try FileManager.default.createDirectory(
                at: directory,
                withIntermediateDirectories: true
            )
            try data.write(to: fileURL, options: .atomic)
        } catch {
            // Losing this cache only creates a new controller on next launch.
        }
    }

    public static var defaultFileURL: URL {
        FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        )[0]
        .appendingPathComponent("Relay", isDirectory: true)
        .appendingPathComponent(
            "controller-thread-id-v\(RelayControllerInstructions.revision)"
        )
    }

    public static var attentionClassifierFileURL: URL {
        FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        )[0]
        .appendingPathComponent("Relay", isDirectory: true)
        .appendingPathComponent("attention-classifier-thread-id-v1")
    }
}
