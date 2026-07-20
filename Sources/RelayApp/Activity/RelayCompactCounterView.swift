import RelayCore
import SwiftUI

struct RelayCompactCounterView: View {
    let counter: RelayCompactCounterPresentation

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isBreathing = false
    @State private var scale = 1.0
    @State private var emphasisOffset = 0.0
    @State private var showsReadyCheck = false

    var body: some View {
        ZStack {
            if counter.state == .running {
                Circle()
                    .stroke(color.opacity(0.30), lineWidth: 1)
                    .scaleEffect(isBreathing ? 1.18 : 0.92)
                    .opacity(isBreathing ? 0.18 : 0.55)
            }

            Circle()
                .fill(color)

            if counter.state == .ready, showsReadyCheck {
                Image(systemName: "checkmark")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(.white)
            } else {
                Text(counter.displayValue)
                    .font(
                        .system(
                            size: 10,
                            weight: .semibold,
                            design: .rounded
                        )
                    )
                    .foregroundStyle(.white)
                    .minimumScaleFactor(0.78)
                    .lineLimit(1)
            }
        }
        .frame(
            width: RelayNotchSafeArea.compactCounterDiameter,
            height: RelayNotchSafeArea.compactCounterDiameter
        )
        .scaleEffect(scale)
        .offset(x: emphasisOffset)
        .animation(runningAnimation, value: isBreathing)
        .task(id: counter) {
            await performOneShotEmphasis()
        }
        .task(id: animatesContinuously) {
            isBreathing = animatesContinuously
        }
        .accessibilityHidden(true)
    }

    private var animatesContinuously: Bool {
        counter.state == .running
            && RelayAccessibilityContract.allowsLoopingStatusMotion(
                reduceMotion: reduceMotion
            )
    }

    private var runningAnimation: Animation? {
        guard animatesContinuously else { return nil }
        return .easeInOut(duration: 1.8).repeatForever(
            autoreverses: true
        )
    }

    private func performOneShotEmphasis() async {
        showsReadyCheck = counter.state == .ready
        emphasisOffset = 0

        guard !reduceMotion else {
            scale = 1
            if showsReadyCheck {
                do {
                    try await Task.sleep(for: .milliseconds(550))
                } catch {
                    return
                }
                showsReadyCheck = false
            }
            return
        }

        scale = 0.74
        withAnimation(.easeOut(duration: 0.18)) {
            scale = 1
        }

        if counter.state == .failed {
            do {
                for offset in [-1.5, 1.5, 0.0] {
                    try await Task.sleep(for: .milliseconds(75))
                    withAnimation(.easeOut(duration: 0.075)) {
                        emphasisOffset = offset
                    }
                }
            } catch {
                return
            }
        }

        if showsReadyCheck {
            do {
                try await Task.sleep(for: .milliseconds(550))
            } catch {
                return
            }
            showsReadyCheck = false
        }
    }

    private var color: Color {
        switch counter.state {
        case .needsInput: RelayPalette.needsInput
        case .failed: RelayPalette.failed
        case .ready: RelayPalette.ready
        case .running: RelayPalette.running
        case .idle: RelayPalette.idle
        }
    }
}
