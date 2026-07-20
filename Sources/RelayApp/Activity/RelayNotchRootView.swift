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
    let usageActions: RelayUsageActions
    let autoApplyResetCredits: Bool
    let settings: RelaySettingsStore
    let settingsErrorMessage: String?
    @Binding var commandText: String
    let composerPhase: RelayComposerPhase
    let voiceActivity: RelayVoiceActivity
    let voiceSetup: RelayVoiceSetupPresentation?
    let isResolvingVoiceSetup: Bool
    let chatMessages: [RelayChatMessage]
    let connection: RelayConnectionPresentation?
    let safeArea: RelayNotchSafeArea
    let submitCommand: () -> Void
    let retryConnection: () -> Void
    let performVoiceSetupPrimaryAction: () -> Void
    let dismissVoiceSetup: () -> Void
    let submitPendingAnswers:
        (String, [String: [String]]) async throws -> Void
    let submitPendingDecision:
        (String, RelayPendingApprovalDecision) async throws -> Void
    let requestPresentation: (RelayPanelPresentation) -> Void
    let pointerHoverChanged: (Bool) -> Void
    let priorityActivityChanged: (RelayAutomaticPeekTrigger?) -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var selectedSection = RelayExpandedSection.activity

    var body: some View {
        ZStack {
            notchShape
                .fill(shellFill)

            if presentation == .expanded {
                RelayAmbientLightView(
                    state: activity.compactState,
                    isExpanded: true
                )
            }

            if presentation == .expanded {
                VStack(spacing: 0) {
                    Color.black
                        .frame(height: expandedHeaderStripHeight)
                    Spacer(minLength: 0)
                }
                .accessibilityHidden(true)
                .allowsHitTesting(false)
            }

            Group {
                switch presentation {
                case .hidden:
                    EmptyView()
                case .peek:
                    RelayPeekView(
                        activity: activity,
                        safeArea: safeArea,
                        expand: expand
                    )
                case .compact:
                    RelayCompactActivityView(
                        activity: activity,
                        voiceActivity: voiceActivity,
                        safeArea: safeArea,
                        expand: expand
                    )
                case .expanded:
                    RelayExpandedActivityView(
                        activity: activity,
                        capacity: capacity,
                        tokenUsageByThreadID: tokenUsageByThreadID,
                        pendingInteractions: pendingInteractions,
                        drafts: drafts,
                        actions: actions,
                        usageActions: usageActions,
                        autoApplyResetCredits: autoApplyResetCredits,
                        settings: settings,
                        settingsErrorMessage: settingsErrorMessage,
                        selectedSection: $selectedSection,
                        commandText: $commandText,
                        composerPhase: composerPhase,
                        chatMessages: chatMessages,
                        connection: connection,
                        safeArea: safeArea,
                        submitCommand: submitCommand,
                        retryConnection: retryConnection,
                        submitPendingAnswers: submitPendingAnswers,
                        submitPendingDecision: submitPendingDecision,
                        collapse: collapse
                    )
                }
            }

            if presentation == .expanded, let voiceSetup {
                Color.black.opacity(0.58)
                    .accessibilityHidden(true)

                VStack {
                    Spacer(minLength: safeArea.topInset + 24)
                    RelayVoiceSetupView(
                        presentation: voiceSetup,
                        isResolving: isResolvingVoiceSetup,
                        performPrimaryAction: performVoiceSetupPrimaryAction,
                        dismiss: dismissVoiceSetup
                    )
                    .padding(.horizontal, 24)
                    Spacer(minLength: 24)
                }
                .transition(voiceSetupTransition)
            }
        }
        .clipShape(notchShape)
        .overlay {
            if presentation == .expanded {
                notchShape
                    .stroke(edgeLighting, lineWidth: 1)
                    .mask {
                        VStack(spacing: 0) {
                            Color.clear
                                .frame(height: expandedHeaderStripHeight)
                            Color.white
                        }
                    }
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)
            }
        }
        .contentShape(notchShape)
        .tint(RelayPalette.accent)
        .animation(contentAnimation, value: voiceSetup)
        .onHover(perform: pointerHoverChanged)
        .onChange(of: automaticPeekTrigger, initial: true) {
            _, trigger in priorityActivityChanged(trigger)
        }
        .onChange(of: chatMessages.count) { previousCount, count in
            selectedSection = RelayExpandedSection.selection(
                preserving: selectedSection,
                previousChatMessageCount: previousCount,
                chatMessageCount: count
            )
        }
        .onChange(of: draftOwners, initial: true) { _, owners in
            drafts.reconcile(
                liveThreadIDs: owners.threadIDs,
                liveInteractionIDs: owners.interactionIDs
            )
        }
    }

    private var automaticPeekTrigger: RelayAutomaticPeekTrigger? {
        RelayAutomaticPeekPolicy.trigger(
            activity.automaticPeekTrigger,
            enabled: settings.automaticPeeks
        )
    }

    private var contentAnimation: Animation {
        switch RelayAccessibilityContract.motionStyle(
            reduceMotion: reduceMotion
        ) {
        case .crossfade:
            .linear(duration: 0.12)
        case .anchoredMovement:
            .timingCurve(0.22, 1, 0.36, 1, duration: 0.22)
        }
    }

    private var voiceSetupTransition: AnyTransition {
        switch RelayAccessibilityContract.motionStyle(
            reduceMotion: reduceMotion
        ) {
        case .crossfade:
            .opacity
        case .anchoredMovement:
            .opacity.combined(with: .scale(scale: 0.98))
        }
    }

    private var notchShape: RelayNotchDropShape {
        RelayNotchDropShape(
            bottomRadius: presentation == .expanded ? 28 : 15
        )
    }

    private var edgeLighting: LinearGradient {
        LinearGradient(
            colors: [
                Color.white.opacity(0.13),
                RelayPalette.accent.opacity(0.48),
                RelayPalette.accentHighlight.opacity(0.20),
                Color.white.opacity(0.07),
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    private var shellLighting: LinearGradient {
        LinearGradient(
            colors: [
                RelayPalette.shellRaised,
                RelayPalette.shell,
            ],
            startPoint: .top,
            endPoint: .bottom
        )
    }

    private var shellFill: AnyShapeStyle {
        switch presentation {
        case .peek, .compact:
            AnyShapeStyle(.black)
        case .hidden, .expanded:
            AnyShapeStyle(shellLighting)
        }
    }

    private var expandedHeaderStripHeight: CGFloat {
        max(
            CGFloat(safeArea.topInset),
            RelayExpandedHeader.height
        )
    }

    private func expand() {
        requestPresentation(.expanded)
    }

    private func collapse() {
        guard drafts.canDismiss else { return }
        requestPresentation(.compact)
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
