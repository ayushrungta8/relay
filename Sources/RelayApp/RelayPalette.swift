import SwiftUI

enum RelayPalette {
    static let accent = Color(
        red: 0.18,
        green: 0.48,
        blue: 0.30
    )

    static let hoverSurface = Color(
        red: 0.055,
        green: 0.085,
        blue: 0.066
    )
    static let shell = Color(
        red: 0.012,
        green: 0.015,
        blue: 0.014
    )
    static let elevatedSurface = Color(
        red: 0.035,
        green: 0.041,
        blue: 0.038
    )
    static let elevatedHover = Color(
        red: 0.065,
        green: 0.075,
        blue: 0.070
    )
    static let hairline = Color.white.opacity(0.10)
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
