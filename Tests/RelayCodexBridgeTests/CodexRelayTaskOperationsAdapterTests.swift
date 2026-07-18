import Foundation
import RelayCodexBridge
import RelayCodexClient
import Testing

struct CodexRelayTaskOperationsAdapterTests {
    @Test
    func workerDiscoveryReadsEveryPage() async throws {
        let rpc = TaskAdapterRPCStub(paginated: true)
        let adapter = CodexRelayTaskOperationsAdapter(
            client: CodexTaskOperationsClient(rpc: rpc)
        )

        let tasks = try await adapter.listTasks()

        #expect(tasks.map(\.id) == ["worker-1", "worker-2"])
        #expect(await rpc.recordedMethods() == ["thread/list", "thread/list"])
    }

    @Test
    func excludesTheControllerFromWorkerDiscovery() async throws {
        let rpc = TaskAdapterRPCStub()
        let store = TaskAdapterControllerStore(id: "controller-by-id")
        let adapter = CodexRelayTaskOperationsAdapter(
            client: CodexTaskOperationsClient(rpc: rpc),
            controllerThreadStore: store
        )

        let tasks = try await adapter.listTasks()

        #expect(tasks.map(\.id) == ["worker-1"])
        #expect(
            try await adapter.getTask(id: "controller-by-id") == nil
        )
        #expect(
            try await adapter.getTask(id: "controller-by-name") == nil
        )
        #expect(await rpc.readIDs() == ["controller-by-name"])
    }

    @Test
    func refusesToSteerOrInterruptTheController() async throws {
        let rpc = TaskAdapterRPCStub()
        let store = TaskAdapterControllerStore(id: "controller-by-id")
        let adapter = CodexRelayTaskOperationsAdapter(
            client: CodexTaskOperationsClient(rpc: rpc),
            controllerThreadStore: store
        )

        await #expect(throws: CodexRelayTaskOperationsError.self) {
            try await adapter.sendToTask(
                id: "controller-by-id",
                prompt: "Manage yourself"
            )
        }
        await #expect(throws: CodexRelayTaskOperationsError.self) {
            try await adapter.interruptTask(id: "controller-by-id")
        }
        #expect(await rpc.recordedMethods().isEmpty)
    }
}

private actor TaskAdapterControllerStore:
    RelayControllerThreadStoring
{
    private let id: String?

    init(id: String?) {
        self.id = id
    }

    func loadThreadID() -> String? {
        id
    }

    func saveThreadID(_ id: String) {}
}

private actor TaskAdapterRPCStub: CodexRPCRequesting {
    private var requests: [(String, JSONValue)] = []
    private let paginated: Bool

    init(paginated: Bool = false) {
        self.paginated = paginated
    }

    func requestJSON(
        method: String,
        params: JSONValue,
        timeout: Duration
    ) async throws -> JSONValue {
        requests.append((method, params))
        switch method {
        case "thread/list":
            if paginated {
                if params["cursor"]?.stringValue == "page-2" {
                    return .object([
                        "data": .array([
                            Self.thread(id: "worker-2", name: "Second worker"),
                        ]),
                        "nextCursor": .null,
                    ])
                }
                return .object([
                    "data": .array([
                        Self.thread(id: "worker-1", name: "First worker"),
                    ]),
                    "nextCursor": .string("page-2"),
                ])
            }
            return .object([
                "data": .array([
                    Self.thread(
                        id: "controller-by-id",
                        name: "Something stale"
                    ),
                    Self.thread(
                        id: "controller-by-name",
                        name: "Relay Controller"
                    ),
                    Self.thread(
                        id: "worker-1",
                        name: "Research hotels"
                    ),
                ]),
            ])
        case "thread/read":
            let id = params["threadId"]?.stringValue ?? "unknown"
            return .object([
                "thread": Self.thread(
                    id: id,
                    name: id == "controller-by-name"
                        ? "Relay Controller"
                        : "Research hotels"
                ),
            ])
        default:
            return .object([:])
        }
    }

    func recordedMethods() -> [String] {
        requests.map(\.0)
    }

    func readIDs() -> [String] {
        requests.compactMap { method, params in
            guard method == "thread/read" else { return nil }
            return params["threadId"]?.stringValue
        }
    }

    private static func thread(
        id: String,
        name: String
    ) -> JSONValue {
        .object([
            "id": .string(id),
            "name": .string(name),
            "preview": .string(name),
            "cwd": .string("/Users/test/Work"),
            "updatedAt": .integer(1_784_210_400),
            "status": .object(["type": .string("idle")]),
            "turns": .array([]),
        ])
    }
}
