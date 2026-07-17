public struct RelayShortcutModifiers:
    OptionSet,
    Codable,
    Hashable,
    Sendable
{
    public let rawValue: UInt8

    public init(rawValue: UInt8) {
        self.rawValue = rawValue
    }

    public static let command = Self(rawValue: 1 << 0)
    public static let option = Self(rawValue: 1 << 1)
    public static let control = Self(rawValue: 1 << 2)
    public static let shift = Self(rawValue: 1 << 3)
}

public struct RelayGlobalShortcut:
    Codable,
    Equatable,
    Sendable
{
    public let keyCode: UInt32
    public let modifiers: RelayShortcutModifiers

    public init(
        keyCode: UInt32,
        modifiers: RelayShortcutModifiers
    ) {
        self.keyCode = keyCode
        self.modifiers = modifiers
    }

    public static let optionSpace = Self(
        keyCode: 49,
        modifiers: [.option]
    )

    public static let `default` = optionSpace
}
