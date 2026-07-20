struct RelayNotchSafeArea: Equatable, Sendable {
    static let minimumClearanceWidth = 190.0
    static let horizontalPadding = 24.0
    static let compactOuterPadding = 14.0
    static let minimumCompactEarWidth = 96.0

    let topInset: Double
    let obstructionWidth: Double

    var contentClearanceWidth: Double {
        max(
            Self.minimumClearanceWidth,
            obstructionWidth + Self.horizontalPadding
        )
    }

    var minimumCompactPanelWidth: Double {
        contentClearanceWidth
            + 2 * (
                Self.compactOuterPadding
                    + Self.minimumCompactEarWidth
            )
    }
}
