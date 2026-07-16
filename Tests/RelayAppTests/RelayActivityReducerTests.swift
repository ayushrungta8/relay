import RelayCodexClient
import RelayCore
import Testing
@testable import RelayApp

struct RelayActivityReducerTests {
    @Test
    func ordersAttentionByAuthoritativePriorityThenRecency() {
        var reducer = RelayActivityReducer()

        reducer.merge(
            snapshot: RelayMonitoringSnapshot(
                tasks: [
                    activity(
                        id: "ready-newer",
                        updatedAt: 500,
                        status: .idle
                    ),
                    activity(
                        id: "running-newest",
                        updatedAt: 600,
                        status: .active
                    ),
                    activity(
                        id: "failed-older",
                        updatedAt: 100,
                        status: .systemError
                    ),
                    activity(
                        id: "waiting-oldest",
                        updatedAt: 50,
                        status: .active,
                        activeFlags: [.waitingOnUserInput]
                    ),
                    activity(
                        id: "ready-older",
                        updatedAt: 400,
                        status: .idle
                    ),
                ],
                usage: nil
            )
        )
        reducer.merge(
            event: .threadStatusChanged(
                threadID: "ready-newer",
                status: .active,
                activeFlags: []
            )
        )
        reducer.merge(
            event: .threadStatusChanged(
                threadID: "ready-newer",
                status: .idle,
                activeFlags: []
            )
        )
        reducer.merge(
            event: .threadStatusChanged(
                threadID: "ready-older",
                status: .active,
                activeFlags: []
            )
        )
        reducer.merge(
            event: .threadStatusChanged(
                threadID: "ready-older",
                status: .idle,
                activeFlags: []
            )
        )

        #expect(
            reducer.attentionTasks.map(\.id)
                == [
                    "waiting-oldest",
                    "failed-older",
                    "ready-newer",
                    "ready-older",
                ]
        )
        #expect(reducer.runningTasks.map(\.id) == ["running-newest"])
    }

    @Test
    func unreadCompletionPersistsAcrossSnapshotsUntilMarkedRead() {
        var reducer = RelayActivityReducer()
        reducer.merge(
            snapshot: RelayMonitoringSnapshot(
                tasks: [
                    activity(id: "worker", updatedAt: 100, status: .active),
                ],
                usage: nil
            )
        )
        reducer.merge(
            snapshot: RelayMonitoringSnapshot(
                tasks: [
                    activity(id: "worker", updatedAt: 200, status: .idle),
                ],
                usage: nil
            )
        )
        reducer.merge(
            snapshot: RelayMonitoringSnapshot(
                tasks: [
                    activity(id: "worker", updatedAt: 300, status: .idle),
                ],
                usage: nil
            )
        )

        #expect(reducer.attentionTasks.first?.id == "worker")
        #expect(reducer.attentionTasks.first?.hasUnreadCompletion == true)

        reducer.markRead(threadID: "worker")

        #expect(reducer.attentionTasks.isEmpty)
        #expect(reducer.recentTasks.first?.id == "worker")
        #expect(reducer.recentTasks.first?.hasUnreadCompletion == false)
        #expect(reducer.lastSelectedThreadID == "worker")
    }

    @Test
    func onlyIdleOrFailureTransitionsCreateUnreadActivity() {
        var reducer = RelayActivityReducer()
        reducer.merge(
            snapshot: RelayMonitoringSnapshot(
                tasks: [
                    activity(id: "worker", updatedAt: 100, status: .active),
                ],
                usage: nil
            )
        )

        reducer.merge(
            event: .threadStatusChanged(
                threadID: "worker",
                status: .notLoaded,
                activeFlags: []
            )
        )

        #expect(reducer.recentTasks.first?.hasUnreadCompletion == false)
    }

    @Test
    func hidesUnnamedControllerUsingItsAuthoritativeStoredID() {
        var reducer = RelayActivityReducer()

        reducer.merge(
            snapshot: RelayMonitoringSnapshot(
                tasks: [
                    activity(
                        id: "controller",
                        updatedAt: 200,
                        status: .active
                    ),
                    activity(
                        id: "worker",
                        updatedAt: 100,
                        status: .active
                    ),
                ],
                usage: nil
            ),
            controllerThreadID: "controller"
        )

        #expect(reducer.runningTasks.map(\.id) == ["worker"])
    }

    @Test
    func initiallyFailedTaskIsNotMarkedUnreadWithoutATransition() {
        var reducer = RelayActivityReducer()

        reducer.merge(
            snapshot: RelayMonitoringSnapshot(
                tasks: [
                    activity(
                        id: "failed",
                        updatedAt: 100,
                        status: .systemError
                    ),
                ],
                usage: nil
            )
        )

        #expect(reducer.attentionTasks.first?.id == "failed")
        #expect(
            reducer.attentionTasks.first?.hasUnreadCompletion == false
        )
    }

    private func activity(
        id: String,
        updatedAt: Int,
        status: CodexThreadStatus,
        activeFlags: [CodexThreadActiveFlag] = []
    ) -> RelayTaskActivity {
        RelayTaskActivity(
            thread: CodexThread(
                id: id,
                preview: id,
                cwd: "/tmp",
                updatedAt: updatedAt,
                status: status,
                activeFlags: activeFlags
            )
        )
    }
}
