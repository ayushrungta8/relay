import AppKit

struct RelayPanelClick: Equatable, Sendable {
    let screenLocation: CGPoint

    init(globalEvent: NSEvent) {
        screenLocation = globalEvent.locationInWindow
    }
}
