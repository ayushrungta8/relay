struct RelayTaskOperationState: Equatable {
    private var sendingTaskIDs: Set<String> = []
    private var errorsByTaskID: [String: String] = [:]

    mutating func beginSending(taskID: String) -> Bool {
        guard sendingTaskIDs.insert(taskID).inserted else { return false }
        errorsByTaskID.removeValue(forKey: taskID)
        return true
    }

    mutating func finishSending(taskID: String, error: String?) {
        sendingTaskIDs.remove(taskID)
        if let error {
            errorsByTaskID[taskID] = error
        } else {
            errorsByTaskID.removeValue(forKey: taskID)
        }
    }

    func isSending(taskID: String) -> Bool {
        sendingTaskIDs.contains(taskID)
    }

    mutating func recordError(_ error: String?, taskID: String) {
        if let error {
            errorsByTaskID[taskID] = error
        } else {
            errorsByTaskID.removeValue(forKey: taskID)
        }
    }

    func error(taskID: String) -> String? {
        errorsByTaskID[taskID]
    }
}
