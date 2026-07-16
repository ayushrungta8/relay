import RelayCore
import SwiftUI

struct RelayNotchRootView: View {
    let presentation: RelayPanelPresentation
    let activity: RelayActivityPresentation
    let capacity: RelayCapacityPresentation
    let tokenUsageByThreadID: [String: RelayThreadTokenUsage]
    let pendingInteractions: [RelayPendingInteraction]
    let actions: RelayTaskActions
    @Binding var commandText: String
    let composerPhase: RelayComposerPhase
    let topInset: Double
    let submitCommand: () -> Void
    let submitPendingAnswers:
        (String, [String: [String]]) async throws -> Void
    let submitPendingDecision:
        (String, RelayPendingApprovalDecision) async throws -> Void
    let requestPresentation: (RelayPanelPresentation) -> Void
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
                        actions: actions,
                        commandText: $commandText,
                        composerPhase: composerPhase,
                        submitCommand: submitCommand,
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
    }

    private var contentAnimation: Animation {
        reduceMotion
            ? .linear(duration: 0.12)
            : .easeOut(duration: 0.2)
    }

    private var contentTransition: AnyTransition {
        if reduceMotion {
            return .opacity
        }
        return .opacity.combined(with: .offset(y: -8))
    }

    private func expand() {
        requestPresentation(.expanded)
    }

    private func collapse() {
        requestPresentation(.compact)
    }

    private func reportExpandedHeight(_ height: Double) {
        reportContentHeight(.expanded, height)
    }
}
