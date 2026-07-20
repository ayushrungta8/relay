enum RelayShortcutInputEvent: Equatable, Sendable {
    case keyDown(
        keyCode: UInt32,
        modifiers: RelayShortcutModifiers,
        isRepeat: Bool
    )
    case keyUp(keyCode: UInt32)
    case modifiersChanged(RelayShortcutModifiers)
}

struct RelayShortcutEventState: Sendable {
    private let shortcut: RelayGlobalShortcut
    private var isPressed = false

    init(shortcut: RelayGlobalShortcut) {
        self.shortcut = shortcut
    }

    mutating func handle(
        _ input: RelayShortcutInputEvent
    ) -> RelayGlobalShortcutEvent? {
        switch input {
        case let .keyDown(keyCode, modifiers, isRepeat):
            guard shortcut.keyCode != nil,
                  !isPressed,
                  !isRepeat,
                  keyCode == shortcut.keyCode,
                  modifiers == shortcut.modifiers else {
                return nil
            }
            isPressed = true
            return .pressed

        case let .keyUp(keyCode):
            guard shortcut.keyCode != nil,
                  isPressed,
                  keyCode == shortcut.keyCode else {
                return nil
            }
            isPressed = false
            return .released

        case let .modifiersChanged(modifiers):
            if shortcut.keyCode == nil {
                if !isPressed, modifiers == shortcut.modifiers {
                    isPressed = true
                    return .pressed
                }
                if isPressed, modifiers != shortcut.modifiers {
                    isPressed = false
                    return .released
                }
                return nil
            }
            guard isPressed,
                  !modifiers.contains(shortcut.modifiers) else { return nil }
            isPressed = false
            return .released
        }
    }
}
