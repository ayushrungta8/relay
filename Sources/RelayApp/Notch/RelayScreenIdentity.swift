import AppKit

struct RelayScreenIdentity: Hashable, Sendable {
  let displayID: CGDirectDisplayID

  init(displayID: CGDirectDisplayID) {
    self.displayID = displayID
  }

  init?(screen: NSScreen) {
    let key = NSDeviceDescriptionKey("NSScreenNumber")
    guard let number = screen.deviceDescription[key] as? NSNumber else {
      return nil
    }
    displayID = CGDirectDisplayID(number.uint32Value)
  }

  func resolve(in screens: [NSScreen] = NSScreen.screens) -> NSScreen? {
    screens.first { RelayScreenIdentity(screen: $0) == self }
  }
}
