import RelayCore
import SwiftUI

struct RelayNotchRootView: View {
    let presentation: RelayPanelPresentation
    let activity: RelayActivityPresentation
    let capacity: RelayCapacityPresentation
    let tokenUsageByThreadID: [String: RelayThreadTokenUsage]
    let pendingInteractions: [RelayPendingInteraction]
    let drafts: RelayPanelDraftStore
    let actions: RelayTaskActions
    @Binding var commandText: String
    let composerPhase: RelayComposerPhase
    let latestResponse: String?
    let connection: RelayConnectionPresentation?
    let topInset: Double
    let submitCommand: () -> Void
    let retryConnection: () -> Void
    let submitPendingAnswers:
        (String, [String: [String]]) async throws -> Void
    let submitPendingDecision:
        (String, RelayPendingApprovalDecision) async throws -> Void
    let requestPresentation: (RelayPanelPresentation) -> Void
    let priorityActivityChanged: (RelayAutomaticPeekTrigger?) -> Void
    let reportContentHeight: (RelayPanelPresentation, Double) -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZStack {
            UnevenRoundedRectangle(
                topLeadingRadius: 2,
                bottomLeadingRadius: 16,
                bottomTrailingRadius: 16,
                topTrailingRadius: 2
            )
            .fill(RelayPalette.shell)

            Group {
                switch presentation {
                case .hidden:
                    EmptyView()
                case .peek:
                    RelayPeekView(
                        copy: activity.peekCopy,
                        state: activity.orderedTasks.first?.attentionState
                            ?? .idle
                    )
                    .onGeometryChange(for: Double.self) { proxy in
                        Double(proxy.size.height)
                    } action: { height in
                        reportContentHeight(.peek, height)
                    }
                case .compact:
                    RelayCompactActivityView(
                        activity: activity,
                        capacity: capacity,
                        tokenUsageByThreadID: tokenUsageByThreadID,
                        actions: actions,
                        drafts: drafts,
                        expand: expand
                    )
                    .onGeometryChange(for: Double.self) { proxy in
                        Double(proxy.size.height)
                    } action: { height in
                        reportContentHeight(.compact, height)
                    }
                case .expanded:
                    RelayExpandedActivityView(
                        activity: activity,
                        capacity: capacity,
                        tokenUsageByThreadID: tokenUsageByThreadID,
                        pendingInteractions: pendingInteractions,
                        drafts: drafts,
                        actions: actions,
                        commandText: $commandText,
                        composerPhase: composerPhase,
                        latestResponse: latestResponse,
                        connection: connection,
                        submitCommand: submitCommand,
                        retryConnection: retryConnection,
                        submitPendingAnswers: submitPendingAnswers,
                        submitPendingDecision: submitPendingDecision,
                        collapse: collapse,
                        contentHeightChanged: reportExpandedHeight
                    )
                }
            }
            .padding(.top, topInset)
            .transition(contentTransition)
        }
        .tint(RelayPalette.accent)
        .animation(contentAnimation, value: presentation)
        .onChange(of: activity.automaticPeekTrigger, initial: true) {
            _, trigger in
            priorityActivityChanged(trigger)
        }
        .onChange(of: draftOwners, initial: true) { _, owners in
            drafts.reconcile(
                liveThreadIDs: owners.threadIDs,
                liveInteractionIDs: owners.interactionIDs
            )
        }
    }

    private var contentAnimation: Animation {
        switch RelayAccessibilityContract.motionStyle(
            reduceMotion: reduceMotion
        ) {
        case .crossfade:
            .linear(duration: 0.12)
        case .anchoredMovement:
            .easeOut(duration: 0.2)
        }
    }

    private var contentTransition: AnyTransition {
        switch RelayAccessibilityContract.motionStyle(
            reduceMotion: reduceMotion
        ) {
        case .crossfade:
            .opacity
        case .anchoredMovement:
            .opacity.combined(with: .offset(y: -8))
        }
    }

    private func expand() {
        requestPresentation(.expanded)
    }

    private func collapse() {
        guard drafts.canDismiss else { return }
        requestPresentation(.compact)
    }

    private func reportExpandedHeight(_ height: Double) {
        reportContentHeight(.expanded, height)
    }

    private var draftOwners: RelayDraftOwners {
        let threadIDs = Set(activity.orderedTasks.map(\.id))
        let interactionIDs = Set(
            pendingInteractions.compactMap { interaction in
                threadIDs.contains(interaction.threadID)
                    ? interaction.id
                    : nil
            }
        )
        return RelayDraftOwners(
            threadIDs: threadIDs,
            interactionIDs: interactionIDs
        )
    }

}
