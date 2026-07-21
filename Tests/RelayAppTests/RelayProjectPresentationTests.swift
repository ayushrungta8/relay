import Foundation
import Testing
@testable import RelayApp

struct RelayProjectPresentationTests {
    private let homeDirectory = URL(filePath: "/Users/test")

    @Test
    func projectlessChatDirectoryUsesGeneralLabel() {
        let name = RelayProjectPresentation.name(
            for: "/Users/test/Documents/Codex/2026-07-21/help-me-fix-this",
            homeDirectory: homeDirectory
        )

        #expect(name == "General")
    }

    @Test
    func realProjectUsesDirectoryName() {
        let name = RelayProjectPresentation.name(
            for: "/Users/test/Work/Relay",
            homeDirectory: homeDirectory
        )

        #expect(name == "Relay")
    }

    @Test
    func codexDirectoryOutsideDatedChatStructureIsPreserved() {
        let name = RelayProjectPresentation.name(
            for: "/Users/test/Documents/Codex/Relay",
            homeDirectory: homeDirectory
        )

        #expect(name == "Relay")
    }

    @Test
    func anotherUsersProjectlessDirectoryIsNotMisclassified() {
        let name = RelayProjectPresentation.name(
            for: "/Users/other/Documents/Codex/2026-07-21/example",
            homeDirectory: homeDirectory
        )

        #expect(name == "example")
    }
}
