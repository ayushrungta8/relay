import Foundation
import Darwin

public actor StdioCodexAppServerTransport: CodexAppServerTransport {
    private let executableURL: URL?
    private let arguments: [String]
    private let maximumFrameBytes: Int

    private var process: Process?
    private var standardInput: FileHandle?
    private var standardOutput: FileHandle?
    private var continuation:
        AsyncThrowingStream<Data, any Error>.Continuation?
    private var readerTask: Task<Void, Never>?

    public init(
        executableURL: URL? = nil,
        arguments: [String] = ["app-server", "--stdio"],
        maximumFrameBytes: Int = 32 * 1_024 * 1_024
    ) {
        self.executableURL = executableURL
        self.arguments = arguments
        self.maximumFrameBytes = maximumFrameBytes
    }

    public func start() async throws
        -> AsyncThrowingStream<Data, any Error> {
        guard process == nil else {
            throw CodexClientError.processLaunchFailed(
                "The transport is already running."
            )
        }
        guard let executableURL = executableURL
            ?? CodexExecutableLocator.locate() else {
            throw CodexClientError.executableNotFound
        }

        let process = Process()
        let inputPipe = Pipe()
        let outputPipe = Pipe()
        process.executableURL = executableURL
        process.arguments = arguments
        process.standardInput = inputPipe
        process.standardOutput = outputPipe
        process.standardError = FileHandle.nullDevice

        let pair = AsyncThrowingStream<Data, any Error>.makeStream(
            bufferingPolicy: .unbounded
        )
        self.process = process
        standardInput = inputPipe.fileHandleForWriting
        standardOutput = outputPipe.fileHandleForReading
        continuation = pair.continuation

        do {
            try process.run()
        } catch {
            cleanUp()
            pair.continuation.finish(throwing: error)
            throw CodexClientError.processLaunchFailed(
                error.localizedDescription
            )
        }

        let output = outputPipe.fileHandleForReading
        let continuation = pair.continuation
        let maximumFrameBytes = maximumFrameBytes
        readerTask = Task { [weak self] in
            await self?.readFrames(
                from: output,
                maximumFrameBytes: maximumFrameBytes,
                continuation: continuation
            )
        }

        return pair.stream
    }

    public func send(_ message: Data) async throws {
        guard let standardInput, process?.isRunning == true else {
            throw CodexClientError.transportClosed
        }

        var frame = message
        frame.append(0x0A)
        do {
            try standardInput.write(contentsOf: frame)
        } catch {
            throw CodexClientError.transportClosed
        }
    }

    public func stop() async {
        guard let process else { return }

        try? standardInput?.close()
        await waitForExit(process, attempts: 12)

        if process.isRunning {
            process.terminate()
            await waitForExit(process, attempts: 12)
        }

        if process.isRunning {
            kill(process.processIdentifier, SIGKILL)
            await waitForExit(process, attempts: 40)
        }

        try? standardOutput?.close()
        readerTask?.cancel()
        continuation?.finish()
        cleanUp()
    }

    private func readFrames(
        from handle: FileHandle,
        maximumFrameBytes: Int,
        continuation: AsyncThrowingStream<Data, any Error>.Continuation
    ) async {
        var buffer = Data()

        do {
            for try await byte in handle.bytes {
                if byte == 0x0A {
                    if buffer.last == 0x0D {
                        buffer.removeLast()
                    }
                    if !buffer.isEmpty {
                        continuation.yield(buffer)
                    }
                    buffer.removeAll(keepingCapacity: true)
                    continue
                }

                buffer.append(byte)
                guard buffer.count <= maximumFrameBytes else {
                    throw CodexClientError.malformedResponse
                }
            }

            if !buffer.isEmpty {
                continuation.yield(buffer)
            }
            continuation.finish()
        } catch is CancellationError {
            continuation.finish()
        } catch {
            continuation.finish(throwing: error)
        }
    }

    private func waitForExit(_ process: Process, attempts: Int) async {
        for _ in 0..<attempts {
            guard process.isRunning else { return }
            try? await Task.sleep(for: .milliseconds(25))
        }
    }

    private func cleanUp() {
        process = nil
        standardInput = nil
        standardOutput = nil
        continuation = nil
        readerTask = nil
    }
}
