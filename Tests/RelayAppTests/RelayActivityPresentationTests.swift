import Foundation
import RelayCore
import SwiftUI
import Testing
@testable import RelayApp

@MainActor
struct RelayActivityPresentationTests {
    @Test
    func compactSummaryPrioritizesAttentionAndRetainsRunningCount() {
        let presentation = RelayActivityPresentation(
            tasks: [
                activity(
                    id: "waiting",
                    title: "Choose a layout",
                    updatedAt: 300,
                    status: .active,
                    activeFlags: [.waitingOnUserInput]
                ),
                activity(
                    id: "running-one",
                    title: "Build the tray",
                    updatedAt: 200,
                    status: .active
                ),
                activity(
                    id: "running-two",
                    title: "Polish the motion",
                    updatedAt: 100,
                    status: .active
                ),
            ]
        )

        #expect(presentation.compactPrimaryCopy == "1 needs you")
        #expect(presentation.compactSecondaryCopy == "2 running")
        #expect(presentation.compactState == .needsInput)
    }

    @Test
    func compactSummaryIsAllClearWithoutActiveWork() {
        let presentation = RelayActivityPresentation(tasks: [])

        #expect(presentation.compactPrimaryCopy == "All clear")
        #expect(presentation.compactSecondaryCopy == nil)
        #expect(presentation.compactState == .idle)
    }

    @Test
    func peekCopySurfacesAttentionBeforeRunningWork() {
        let presentation = RelayActivityPresentation(
            tasks: [
                activity(
                    id: "running",
                    title: "Build the tray",
                    updatedAt: 300,
                    status: .active
                ),
                activity(
                    id: "waiting",
                    title: "Choose a layout",
                    updatedAt: 100,
                    status: .active,
                    activeFlags: [.waitingOnUserInput]
                ),
            ]
        )

        #expect(presentation.peekCopy == "Choose a layout needs input")
    }

    @Test
    func expandedSummaryUsesSingularTaskGrammar() {
        let presentation = RelayActivityPresentation(
            tasks: [
                activity(
                    id: "waiting",
                    title: "Choose a layout",
                    updatedAt: 100,
                    status: .active,
                    activeFlags: [.waitingOnUserInput]
                ),
            ]
        )

        #expect(presentation.expandedSummaryCopy == "1 task needs attention")
    }

    @Test
    func ordersTasksByAttentionPriorityThenRecency() {
        let presentation = RelayActivityPresentation(
            tasks: [
                activity(
                    id: "running-newest",
                    title: "Running",
                    updatedAt: 500,
                    status: .active
                ),
                activity(
                    id: "failed",
                    title: "Failed",
                    updatedAt: 200,
                    status: .systemError
                ),
                activity(
                    id: "waiting",
                    title: "Waiting",
                    updatedAt: 100,
                    status: .active,
                    activeFlags: [.waitingOnApproval]
                ),
                activity(
                    id: "idle",
                    title: "Idle",
                    updatedAt: 600,
                    status: .idle
                ),
            ]
        )

        #expect(
            presentation.orderedTasks.map(\.id)
                == ["waiting", "failed", "running-newest", "idle"]
        )
        #expect(presentation.attentionTasks.map(\.id) == ["waiting", "failed"])
        #expect(presentation.runningTasks.map(\.id) == ["running-newest"])
        #expect(presentation.recentTasks.map(\.id) == ["idle"])
    }

    @Test
    func capacityLabelsComeFromBackendWindowDurations() throws {
        let presentation = RelayCapacityPresentation(
            snapshot: RelayUsageSnapshot(
                limitName: "Codex Pro",
                primary: RelayRateLimitWindow(
                    usedPercent: 42,
                    windowDurationMins: 300,
                    resetsAt: 1_800_000_000
                ),
                secondary: RelayRateLimitWindow(
                    usedPercent: 68,
                    windowDurationMins: 10_080,
                    resetsAt: 1_800_604_800
                )
            )
        )

        #expect(presentation.title == "Codex Pro")
        #expect(try #require(presentation.primary).label == "5-hour window")
        #expect(try #require(presentation.secondary).label == "7-day window")
    }

    @Test
    func missingCapacityRemainsHonestlyUnavailable() {
        let presentation = RelayCapacityPresentation(snapshot: nil)

        #expect(presentation.primary == nil)
        #expect(presentation.secondary == nil)
        #expect(presentation.availabilityCopy == "Usage unavailable")
        #expect(presentation.resetCreditsCopy == "Reset credits unavailable")
    }

    @Test
    func capacityTimestampsIncludeTheFullCalendarDate() throws {
        let utc = try #require(TimeZone(secondsFromGMT: 0))
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = utc
        let date = try #require(
            calendar.date(
                from: DateComponents(
                    year: 2027,
                    month: 11,
                    day: 15,
                    hour: 13
                )
            )
        )

        let label = RelayCapacityPresentation.timestampLabel(
            for: date,
            locale: Locale(identifier: "en_US"),
            timeZone: utc
        )

        #expect(label.contains("2027"))
        #expect(label.contains("Nov"))
        #expect(label.contains("15"))
    }

    @Test
    func taskOpenOnlyMarksReadAfterLaunchServicesAcceptsTheURL() async throws {
        var markedThreadIDs: [String] = []
        let task = activity(
            id: "ready",
            title: "Ready task",
            updatedAt: 100,
            status: .idle
        )
        let rejected = RelayTaskOpenAction(
            openURL: { _ in false },
            markRead: { markedThreadIDs.append($0) }
        )

        await #expect(throws: RelayTaskOpenAction.OpenError.self) {
            try await rejected(task)
        }
        #expect(markedThreadIDs.isEmpty)

        let accepted = RelayTaskOpenAction(
            openURL: { _ in true },
            markRead: { markedThreadIDs.append($0) }
        )
        try await accepted(task)

        #expect(markedThreadIDs == ["ready"])
    }

    @Test(arguments: [
        (74, RelayCapacityPresentation.Level.standard),
        (75, RelayCapacityPresentation.Level.warning),
        (89, RelayCapacityPresentation.Level.warning),
        (90, RelayCapacityPresentation.Level.critical),
    ])
    func capacityThresholdsUseWarningAt75AndCriticalAt90(
        usedPercent: Int,
        expected: RelayCapacityPresentation.Level
    ) {
        #expect(
            RelayCapacityPresentation.Level(usedPercent: usedPercent)
                == expected
        )
    }

    @Test
    func capacityLevelsHaveVisiblePlainLanguageLabels() {
        let levels: [RelayCapacityPresentation.Level] = [
            .standard,
            .warning,
            .critical,
        ]

        #expect(levels.map(\.label) == ["Normal", "Warning", "Critical"])
    }

    @Test
    func everyTaskStateHasAPlainLabelAndDistinctSymbol() {
        let states: [RelayTaskAttentionState] = [
            .needsInput,
            .failed,
            .ready,
            .running,
            .idle,
        ]
        let symbols = states.map(RelayStatusSymbol.init(state:))

        #expect(Set(symbols.map(\.systemName)).count == states.count)
        #expect(symbols.allSatisfy { !$0.label.isEmpty })
        #expect(symbols.map(\.label) == [
            "Needs input",
            "Failed",
            "Ready",
            "Running",
            "Idle",
        ])

        let ready = RelayStatusSymbol(state: .ready)
        #expect(ready.iconColor == RelayPalette.ready)
        #expect(ready.labelColor == RelayPalette.primaryText)
        #expect(ready.iconColor != ready.labelColor)
    }

    private func activity(
        id: String,
        title: String,
        updatedAt: Int,
        status: CodexThreadStatus,
        activeFlags: [CodexThreadActiveFlag] = []
    ) -> RelayTaskActivity {
        RelayTaskActivity(
            thread: CodexThread(
                id: id,
                name: title,
                preview: title,
                cwd: "/Users/example/Relay",
                updatedAt: updatedAt,
                status: status,
                activeFlags: activeFlags
            )
        )
    }
}
