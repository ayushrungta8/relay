import SwiftUI

struct RelayCompactSummaryLabel: View {
    let activity: RelayActivityPresentation
    var voiceActivity: RelayVoiceActivity = .inactive
    let safeArea: RelayNotchSafeArea

    var body: some View {
        Group {
            if safeArea.topInset > 0 {
                notchedCounters
            } else {
                notchlessFallback
            }
        }
        .contentShape(.rect)
    }

    private var notchedCounters: some View {
        HStack(spacing: 0) {
            counterSlot(
                activity.compactAttentionCounter,
                horizontalAlignment: .trailing
            )

            Color.clear
                .frame(width: safeArea.compactCenterClearanceWidth)
                .accessibilityHidden(true)

            if voiceActivity.isActive {
                RelayVoiceActivityDot(activity: voiceActivity)
                    .scaleEffect(0.9)
                    .frame(
                        width: RelayNotchSafeArea.compactCounterTargetWidth
                    )
            } else {
                counterSlot(
                    activity.compactRunningCounter,
                    horizontalAlignment: .leading
                )
            }
        }
        .frame(height: safeArea.topInset)
        .animation(counterAnimation, value: activity.compactAttentionCounter)
        .animation(counterAnimation, value: activity.compactRunningCounter)
    }

    private var notchlessFallback: some View {
        ZStack {
            Circle()
                .fill(RelayPalette.shell)

            if voiceActivity.isActive {
                RelayVoiceActivityDot(activity: voiceActivity)
                    .scaleEffect(0.9)
            } else if let counter = activity.compactAttentionCounter
                ?? activity.compactRunningCounter
            {
                RelayCompactCounterView(counter: counter)
            } else {
                Image(systemName: "waveform")
                    .font(.caption)
                    .foregroundStyle(RelayPalette.tertiaryText)
                    .accessibilityHidden(true)
            }
        }
        .frame(
            width: RelayNotchSafeArea.notchlessCompactDiameter,
            height: RelayNotchSafeArea.notchlessCompactDiameter
        )
    }

    private func counterSlot(
        _ counter: RelayCompactCounterPresentation?,
        horizontalAlignment: HorizontalAlignment
    ) -> some View {
        ZStack(
            alignment: Alignment(
                horizontal: horizontalAlignment,
                vertical: .center
            )
        ) {
            Color.clear
            if let counter {
                RelayCompactCounterView(counter: counter)
                    .transition(counterTransition)
            }
        }
        .frame(width: RelayNotchSafeArea.compactCounterTargetWidth)
    }

    private var counterAnimation: Animation {
        if RelayAccessibilityContract.motionStyle(
            reduceMotion: reduceMotion
        ) == .crossfade {
            return .linear(duration: 0.12)
        }
        return .easeOut(duration: 0.18)
    }

    private var counterTransition: AnyTransition {
        if RelayAccessibilityContract.motionStyle(
            reduceMotion: reduceMotion
        ) == .crossfade {
            return .opacity
        }
        return .scale(scale: 0.74).combined(with: .opacity)
    }

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
}
