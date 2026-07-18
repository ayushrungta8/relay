import Foundation

@MainActor
final class RelayPointerDisplayFollower {
  typealias Sleep = @Sendable (Duration) async throws -> Void

  static let dwellDelay = Duration.milliseconds(500)
  static let relocationDuration: TimeInterval = 0.16

  private let sleep: Sleep
  private let relocate: (RelayScreenIdentity) -> Void
  private var candidate: RelayScreenIdentity?
  private var dwellTask: Task<Void, Never>?

  init(
    sleep: @escaping Sleep = { try await Task.sleep(for: $0) },
    relocate: @escaping (RelayScreenIdentity) -> Void
  ) {
    self.sleep = sleep
    self.relocate = relocate
  }

  func observe(
    pointerDisplay: RelayScreenIdentity?,
    currentDisplay: RelayScreenIdentity?,
    presentation: RelayPanelPresentation
  ) {
    guard
      presentation == .compact,
      let pointerDisplay,
      pointerDisplay != currentDisplay
    else {
      cancel()
      return
    }
    guard candidate != pointerDisplay else { return }

    cancel()
    candidate = pointerDisplay
    dwellTask = Task { [weak self, sleep] in
      do {
        try await sleep(Self.dwellDelay)
      } catch {
        return
      }
      guard let self, !Task.isCancelled else { return }
      commit(pointerDisplay)
    }
  }

  func cancel() {
    dwellTask?.cancel()
    dwellTask = nil
    candidate = nil
  }

  private func commit(_ display: RelayScreenIdentity) {
    guard candidate == display else { return }
    dwellTask = nil
    candidate = nil
    relocate(display)
  }

  deinit {
    dwellTask?.cancel()
  }
}
