import SwiftUI

enum RelayPalette {
    static let accent = Color(
        red: 0.98,
        green: 0.39,
        blue: 0.30
    )
    static let accentHighlight = Color(
        red: 1.00,
        green: 0.67,
        blue: 0.31
    )
    static let accentPressed = Color(
        red: 0.84,
        green: 0.27,
        blue: 0.22
    )

    static let hoverSurface = Color(
        red: 0.11,
        green: 0.095,
        blue: 0.12
    )
    static let shell = Color(
        red: 0.035,
        green: 0.031,
        blue: 0.043
    )
    static let shellRaised = Color(
        red: 0.055,
        green: 0.047,
        blue: 0.066
    )
    static let railSurface = Color(
        red: 0.046,
        green: 0.040,
        blue: 0.055
    )
    static let detailSurface = Color(
        red: 0.031,
        green: 0.028,
        blue: 0.039
    )
    static let elevatedSurface = Color(
        red: 0.075,
        green: 0.064,
        blue: 0.087
    )
    static let elevatedHover = Color(
        red: 0.105,
        green: 0.086,
        blue: 0.113
    )
    static let selectedSurface = Color(
        red: 0.155,
        green: 0.070,
        blue: 0.072
    )
    static let selectedBorder = Color(
        red: 0.49,
        green: 0.20,
        blue: 0.19
    )
    static let fieldSurface = Color(
        red: 0.082,
        green: 0.070,
        blue: 0.094
    )
    static let fieldBorder = Color(
        red: 0.20,
        green: 0.16,
        blue: 0.22
    )
    static let hairline = Color.white.opacity(0.095)
    static let edgeGlow = accent.opacity(0.30)
    static let shellShadow = Color.black.opacity(0.80)
    static let primaryText = Color.white
    static let secondaryText = Color.white.opacity(0.72)
    static let tertiaryText = Color.white.opacity(0.50)

    static let running = Color(
        red: 1.00,
        green: 0.67,
        blue: 0.31
    )
    static let needsInput = Color(
        red: 0.98,
        green: 0.39,
        blue: 0.30
    )
    static let ready = Color(
        red: 0.37,
        green: 0.88,
        blue: 0.66
    )
    static let failed = Color(
        red: 1.00,
        green: 0.27,
        blue: 0.34
    )
    static let idle = tertiaryText
    static let warning = running
    static let critical = failed
}
