struct RelayNotchSafeArea: Equatable, Sendable {
    static let minimumClearanceWidth = 190.0
    static let horizontalPadding = 24.0

    let topInset: Double
    let obstructionWidth: Double

    var contentClearanceWidth: Double {
        max(
            Self.minimumClearanceWidth,
            obstructionWidth + Self.horizontalPadding
        )
    }
}
