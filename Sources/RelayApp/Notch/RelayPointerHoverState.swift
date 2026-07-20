import CoreGraphics

struct RelayPointerHoverState {
    private(set) var isInside = false

    static func contains(_ location: CGPoint, in frame: CGRect) -> Bool {
        let frame = frame.standardized
        guard !frame.isEmpty, !frame.isNull else { return false }
        return location.x >= frame.minX
            && location.x <= frame.maxX
            && location.y >= frame.minY
            && location.y <= frame.maxY
    }

    mutating func update(isInside: Bool) -> Bool? {
        guard isInside != self.isInside else { return nil }
        self.isInside = isInside
        return isInside
    }

    mutating func reset() {
        isInside = false
    }
}
