import SwiftUI

enum RelayPalette {
    static let accent = Color(
        red: 0.18,
        green: 0.48,
        blue: 0.30
    )

    static let hoverSurface = accent.opacity(0.08)
    static let shell = Color.black
    static let elevatedSurface = Color.white.opacity(0.075)
    static let elevatedHover = Color.white.opacity(0.12)
    static let hairline = Color.white.opacity(0.12)
    static let primaryText = Color.white
    static let secondaryText = Color.white.opacity(0.72)
    static let tertiaryText = Color.white.opacity(0.54)

    static let running = Color.blue
    static let needsInput = Color.orange
    static let ready = accent
    static let failed = Color.red
    static let idle = Color.secondary
    static let warning = Color.orange
    static let critical = Color.red
}
