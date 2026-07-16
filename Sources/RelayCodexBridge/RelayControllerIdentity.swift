import Foundation

public actor RelayControllerIdentity {
    private let store: any RelayControllerThreadStoring
    private var didAttemptRecovery = false
    private var threadID: String?

    public init(store: any RelayControllerThreadStoring) {
        self.store = store
    }

    public func recoverThreadID() async -> String? {
        if let threadID { return threadID }
        guard !didAttemptRecovery else { return nil }
        didAttemptRecovery = true
        let recovered = await store.loadThreadID()
        if threadID == nil {
            threadID = recovered
        }
        return threadID
    }

    public func activate(threadID: String) async {
        self.threadID = threadID
        didAttemptRecovery = true
        await store.saveThreadID(threadID)
    }

    public func discard(threadID expected: String) {
        guard threadID == expected else { return }
        threadID = nil
    }

    public func currentThreadID() -> String? {
        threadID
    }
}
