struct RelayNotchSafeArea: Equatable, Sendable {
    static let minimumClearanceWidth = 190.0
    static let horizontalPadding = 24.0
    static let peekOuterPadding = 14.0
    static let minimumPeekEarWidth = 96.0
    static let compactCounterDiameter = 18.0
    static let compactCounterTargetWidth = 32.0
    static let compactBoundaryDepth = 3.0
    static let notchlessCompactDiameter = 28.0

    let topInset: Double
    let obstructionWidth: Double

    var contentClearanceWidth: Double {
        max(
            Self.minimumClearanceWidth,
            obstructionWidth + Self.horizontalPadding
        )
    }

    var minimumPeekPanelWidth: Double {
        contentClearanceWidth
            + 2 * (
                Self.peekOuterPadding
                    + Self.minimumPeekEarWidth
            )
    }

    var compactCenterClearanceWidth: Double {
        max(Self.minimumClearanceWidth, obstructionWidth)
    }

    var compactCounterPanelWidth: Double {
        compactCenterClearanceWidth
            + 2 * Self.compactCounterTargetWidth
    }
}
