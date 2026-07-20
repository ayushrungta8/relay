import RelayVoice

struct RelayShortcutCaptureState {
    private var peakModifiers: RelayShortcutModifiers = []

    mutating func modifiersChanged(
        _ modifiers: RelayShortcutModifiers
    ) -> RelayGlobalShortcut? {
        if modifiers.rawValue.nonzeroBitCount
            > peakModifiers.rawValue.nonzeroBitCount {
            peakModifiers = modifiers
            return nil
        }
        guard !peakModifiers.isEmpty, modifiers != peakModifiers else {
            return nil
        }
        defer { peakModifiers = [] }
        return RelayGlobalShortcut(
            keyCode: nil,
            modifiers: peakModifiers
        )
    }

    mutating func keyDown(
        keyCode: UInt32,
        modifiers: RelayShortcutModifiers
    ) -> RelayGlobalShortcut? {
        guard !modifiers.isEmpty else { return nil }
        peakModifiers = []
        return RelayGlobalShortcut(
            keyCode: keyCode,
            modifiers: modifiers
        )
    }
}
