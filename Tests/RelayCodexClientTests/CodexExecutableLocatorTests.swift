import Foundation
import Testing
@testable import RelayCodexClient

struct CodexExecutableLocatorTests {
    @Test
    func honorsAnExecutableCodexPathOverride() throws {
        let directory = FileManager.default.temporaryDirectory
            .appending(path: UUID().uuidString, directoryHint: .isDirectory)
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )
        defer { try? FileManager.default.removeItem(at: directory) }

        let executable = directory.appending(path: "codex")
        #expect(
            FileManager.default.createFile(
                atPath: executable.path,
                contents: Data()
            )
        )
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o755],
            ofItemAtPath: executable.path
        )

        let result = CodexExecutableLocator.locate(
            environment: ["CODEX_PATH": executable.path]
        )

        #expect(result == executable)
    }
}
