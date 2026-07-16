import Foundation

public enum CodexExecutableLocator {
    public static func locate(
        environment: [String: String] = ProcessInfo.processInfo.environment,
        fileManager: FileManager = .default
    ) -> URL? {
        if let override = environment["CODEX_PATH"],
           fileManager.isExecutableFile(atPath: override) {
            return URL(filePath: override)
        }

        let knownPaths = [
            "/Applications/Codex.app/Contents/Resources/codex",
            "/Applications/ChatGPT.app/Contents/Resources/codex",
            "/opt/homebrew/bin/codex",
            "/usr/local/bin/codex",
        ]

        if let knownPath = knownPaths.first(
            where: fileManager.isExecutableFile(atPath:)
        ) {
            return URL(filePath: knownPath)
        }

        for directory in environment["PATH", default: ""].split(separator: ":") {
            let candidate = "\(directory)/codex"
            if fileManager.isExecutableFile(atPath: candidate) {
                return URL(filePath: candidate)
            }
        }

        return nil
    }
}
