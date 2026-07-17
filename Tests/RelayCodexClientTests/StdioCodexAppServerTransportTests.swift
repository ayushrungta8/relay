import Foundation
import Darwin
import Testing
@testable import RelayCodexClient

struct StdioCodexAppServerTransportTests {
    @Test
    func exchangesNewlineDelimitedMessagesWithAChildProcess() async throws {
        let fixture = try FixtureCodexExecutable()
        defer { fixture.remove() }

        let transport = StdioCodexAppServerTransport(
            executableURL: fixture.url,
            arguments: []
        )
        let client = CodexAppServerClient(transport: transport)

        let threads = try await client.loadThreads(limit: 5)

        #expect(threads.map(\.id) == ["fixture-thread"])
        #expect(threads.first?.preview == "A real child process answered")
    }

    @Test
    func forceKillsAChildThatIgnoresGracefulShutdown() async throws {
        let fixture = try StubbornFixtureCodexExecutable()
        var childPID: pid_t?
        defer {
            if let childPID, kill(childPID, 0) == 0 {
                kill(childPID, SIGKILL)
            }
            fixture.remove()
        }

        let transport = StdioCodexAppServerTransport(
            executableURL: fixture.url,
            arguments: [fixture.pidFile.path]
        )
        _ = try await transport.start()
        childPID = try await fixture.waitForPID()

        await transport.stop()

        let isStillRunning = childPID.map { kill($0, 0) == 0 } ?? false
        #expect(!isStillRunning)
    }
}

private struct FixtureCodexExecutable {
    let directory: URL
    let url: URL

    init() throws {
        directory = FileManager.default.temporaryDirectory
            .appending(path: UUID().uuidString, directoryHint: .isDirectory)
        url = directory.appending(path: "codex-fixture")

        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )
        try script.write(to: url, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o755],
            ofItemAtPath: url.path
        )
    }

    func remove() {
        try? FileManager.default.removeItem(at: directory)
    }

    private let script = """
        #!/bin/sh
        while IFS= read -r line
        do
          case "$line" in
            *\\"method\\":\\"initialize\\"*)
              printf '%s\\n' '{"id":1,"result":{"userAgent":"fixture","platformFamily":"unix","platformOs":"macos","codexHome":"/tmp/.codex"}}'
              ;;
            *\\"method\\":\\"thread\\\\/list\\"*)
              printf '%s\\n' '{"id":2,"result":{"data":[{"id":"fixture-thread","preview":"A real child process answered","cwd":"/tmp/Relay","updatedAt":1784210400,"status":{"type":"idle"}}],"nextCursor":null}}'
              ;;
          esac
        done
        """
}

private struct StubbornFixtureCodexExecutable {
    let directory: URL
    let url: URL
    let pidFile: URL

    init() throws {
        directory = FileManager.default.temporaryDirectory
            .appending(path: UUID().uuidString, directoryHint: .isDirectory)
        url = directory.appending(path: "stubborn-codex-fixture")
        pidFile = directory.appending(path: "pid")

        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )
        try script.write(to: url, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o755],
            ofItemAtPath: url.path
        )
    }

    func waitForPID() async throws -> pid_t {
        for _ in 0..<200 {
            if let value = try? String(contentsOf: pidFile, encoding: .utf8),
               let pid = pid_t(value.trimmingCharacters(in: .whitespacesAndNewlines)) {
                return pid
            }
            try await Task.sleep(for: .milliseconds(25))
        }
        throw FixtureError.pidWasNotWritten
    }

    func remove() {
        try? FileManager.default.removeItem(at: directory)
    }

    private let script = """
        #!/bin/sh
        printf '%s' "$$" > "$1"
        trap '' TERM
        while :
        do
          :
        done
        """
}

private enum FixtureError: Error {
    case pidWasNotWritten
}
