import Foundation

enum RelayProjectPresentation {
    nonisolated static func name(
        for workingDirectory: String,
        homeDirectory: URL = .homeDirectory
    ) -> String {
        let directory = URL(filePath: workingDirectory).standardizedFileURL
        if isProjectlessChatDirectory(
            directory,
            homeDirectory: homeDirectory.standardizedFileURL
        ) {
            return "General"
        }

        let name = directory.lastPathComponent
        return name.isEmpty ? workingDirectory : name
    }

    nonisolated private static func isProjectlessChatDirectory(
        _ directory: URL,
        homeDirectory: URL
    ) -> Bool {
        let projectlessRoot = homeDirectory
            .appending(path: "Documents/Codex", directoryHint: .isDirectory)
        let relativeComponents = Array(
            directory.pathComponents.dropFirst(
                projectlessRoot.pathComponents.count
            )
        )

        guard directory.pathComponents.starts(
            with: projectlessRoot.pathComponents
        ),
            relativeComponents.count == 2,
            isDateDirectory(relativeComponents[0])
        else {
            return false
        }

        return !relativeComponents[1].isEmpty
    }

    nonisolated private static func isDateDirectory(_ name: String) -> Bool {
        let components = name.split(
            separator: "-",
            omittingEmptySubsequences: false
        )
        guard components.map(\.count) == [4, 2, 2] else { return false }
        return components.allSatisfy { component in
            component.allSatisfy(\.isNumber)
        }
    }
}
