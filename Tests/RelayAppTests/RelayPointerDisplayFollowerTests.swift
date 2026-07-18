import Foundation
import Testing

@testable import RelayApp

@MainActor
struct RelayPointerDisplayFollowerTests {
  @Test
  func compactRelocatesAfterDwell() async {
    let sleeper = DisplayFollowSleeper()
    var moves: [RelayScreenIdentity] = []
    let follower = RelayPointerDisplayFollower(
      sleep: { try await sleeper.sleep($0) },
      relocate: { moves.append($0) }
    )
    let current = RelayScreenIdentity(displayID: 1)
    let candidate = RelayScreenIdentity(displayID: 2)

    follower.observe(
      pointerDisplay: candidate,
      currentDisplay: current,
      presentation: .compact
    )
    await sleeper.waitUntilSleeping()

    #expect(await sleeper.requestedDuration() == .milliseconds(500))
    #expect(moves.isEmpty)

    await sleeper.resumeAll()
    for _ in 0..<100 where moves.isEmpty { await Task.yield() }
    #expect(moves == [candidate])
  }

  @Test
  func returningToCurrentDisplayCancelsTheMove() async {
    let sleeper = DisplayFollowSleeper()
    var moves: [RelayScreenIdentity] = []
    let follower = RelayPointerDisplayFollower(
      sleep: { try await sleeper.sleep($0) },
      relocate: { moves.append($0) }
    )
    let current = RelayScreenIdentity(displayID: 1)

    follower.observe(
      pointerDisplay: .init(displayID: 2),
      currentDisplay: current,
      presentation: .compact
    )
    await sleeper.waitUntilSleeping()
    follower.observe(
      pointerDisplay: current,
      currentDisplay: current,
      presentation: .compact
    )
    await sleeper.waitUntilIdle()

    #expect(moves.isEmpty)
  }

  @Test(arguments: [
    RelayPanelPresentation.hidden, .peek, .expanded,
  ])
  func nonCompactPresentationsStayPinned(
    presentation: RelayPanelPresentation
  ) async {
    var moves: [RelayScreenIdentity] = []
    let follower = RelayPointerDisplayFollower(
      sleep: { _ in },
      relocate: { moves.append($0) }
    )

    follower.observe(
      pointerDisplay: .init(displayID: 2),
      currentDisplay: .init(displayID: 1),
      presentation: presentation
    )
    for _ in 0..<20 { await Task.yield() }

    #expect(moves.isEmpty)
  }

  @Test
  func newerCandidateInvalidatesTheStaleTask() async {
    let sleeper = DisplayFollowSleeper()
    var moves: [RelayScreenIdentity] = []
    let follower = RelayPointerDisplayFollower(
      sleep: { try await sleeper.sleep($0) },
      relocate: { moves.append($0) }
    )
    let current = RelayScreenIdentity(displayID: 1)
    let second = RelayScreenIdentity(displayID: 3)

    follower.observe(
      pointerDisplay: .init(displayID: 2),
      currentDisplay: current,
      presentation: .compact
    )
    await sleeper.waitUntilSleeping(count: 1)
    follower.observe(
      pointerDisplay: second,
      currentDisplay: current,
      presentation: .compact
    )
    await sleeper.waitUntilSleeping(count: 2)
    await sleeper.resumeAll()
    for _ in 0..<100 where moves.isEmpty { await Task.yield() }

    #expect(moves == [second])
  }
}

private actor DisplayFollowSleeper {
  private struct Request {
    let duration: Duration
    let continuation: CheckedContinuation<Void, any Error>
  }

  private var requestCount = 0
  private var requests: [UUID: Request] = [:]
  private var cancelledBeforeRegistration: Set<UUID> = []

  func sleep(_ duration: Duration) async throws {
    let id = UUID()
    try await withTaskCancellationHandler {
      try await withCheckedThrowingContinuation {
        (continuation: CheckedContinuation<Void, any Error>) in
        requestCount += 1
        if cancelledBeforeRegistration.remove(id) != nil {
          continuation.resume(throwing: CancellationError())
        } else {
          requests[id] = Request(
            duration: duration,
            continuation: continuation
          )
        }
      }
    } onCancel: {
      Task { await self.cancel(id) }
    }
  }

  func waitUntilSleeping(count: Int = 1) async {
    while requestCount < count { await Task.yield() }
  }

  func waitUntilIdle() async {
    while !requests.isEmpty { await Task.yield() }
  }

  func requestedDuration() -> Duration? {
    requests.values.first?.duration
  }

  func resumeAll() {
    let pending = requests.values
    requests.removeAll()
    for request in pending {
      request.continuation.resume()
    }
  }

  private func cancel(_ id: UUID) {
    if let request = requests.removeValue(forKey: id) {
      request.continuation.resume(throwing: CancellationError())
    } else {
      cancelledBeforeRegistration.insert(id)
    }
  }
}
