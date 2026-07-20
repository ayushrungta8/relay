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
    func hidesAttentionClassifierByName() {
        var reducer = RelayActivityReducer()
        reducer.merge(
            snapshot: RelayMonitoringSnapshot(
                tasks: [
                    RelayTaskActivity(
                        thread: CodexThread(
                            id: "classifier",
                            name: "Relay Attention Classifier",
                            preview: "Internal",
                            cwd: "/tmp",
                            updatedAt: 2,
                            status: .active
                        )
                    ),
                    activity(id: "worker", updatedAt: 1, status: .active),
                ],
                usage: nil
            )
        )

        #expect(reducer.runningTasks.map(\.id) == ["worker"])
    }

    @Test
    func ignoresStaleInferredAttentionUpdate() {
        var reducer = RelayActivityReducer()
        let response = RelayTaskFinalResponse(
            turnID: "current-turn",
            text: "Should I proceed?",
            fingerprint: "abc"
        )
        reducer.merge(snapshot: .init(
            tasks: [RelayTaskActivity(
                thread: CodexThread(
                    id: "worker",
                    preview: "Worker",
                    cwd: "/tmp",
                    updatedAt: 1,
                    status: .idle
                ),
                latestTurnStatus: .completed,
                latestFinalResponse: response
            )],
            usage: nil
        ))

        reducer.applyInferredAttention(
            threadID: "worker",
            turnID: "stale-turn",
            needsReply: true
        )
        #expect(reducer.recentTasks.first?.attentionState == .idle)

        reducer.applyInferredAttention(
            threadID: "worker",
            turnID: "current-turn",
            needsReply: true
        )
        #expect(reducer.attentionTasks.first?.attentionState == .needsInput)
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

    @Test
    func snapshotClearsCurrentSelectionButRetainsLastInteraction() {
        var reducer = RelayActivityReducer()
        reducer.merge(snapshot: .init(
            tasks: [activity(id: "worker", updatedAt: 1, status: .active)],
            usage: nil
        ))
        reducer.select(threadID: "worker")

        reducer.merge(snapshot: .init(tasks: [], usage: nil))

        #expect(reducer.selectedThreadID == nil)
        #expect(reducer.lastSelectedThreadID == "worker")
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
