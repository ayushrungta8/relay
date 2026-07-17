import SwiftUI

/// Transient voice-interaction state surfaced in the notch header. When
/// `.inactive`, the header shows its usual task summary ("All clear"); the
/// other cases replace that copy while a voice exchange is underway.
enum RelayVoiceActivity: Equatable {
    case inactive
    case listening
    case thinking
    case speaking

    var isActive: Bool {
        self != .inactive
    }

    var label: String {
        switch self {
        case .inactive: ""
        case .listening: "Listening…"
        case .thinking: "Thinking…"
        case .speaking: "Speaking…"
        }
    }

    var tint: Color {
        switch self {
        case .inactive: RelayPalette.idle
        case .listening: RelayPalette.voiceListening
        case .thinking: RelayPalette.voiceThinking
        case .speaking: RelayPalette.voiceSpeaking
        }
    }

    /// Every active state pulses; the tempo differs so they feel distinct
    /// beyond color alone.
    var pulses: Bool {
        isActive
    }

    /// Pulse period in seconds — attentive while listening, a slow breath
    /// while thinking, lively while speaking.
    var pulsePeriod: Double {
        switch self {
        case .listening: 0.9
        case .thinking: 1.4
        case .speaking: 0.65
        case .inactive: 0
        }
    }
}

/// The header status dot while a voice exchange is active — a tinted core
/// with a soft halo that pulses for the live states, respecting Reduce
/// Motion via ``RelayAccessibilityContract``.
struct RelayVoiceActivityDot: View {
    let activity: RelayVoiceActivity

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isExpanded = false

    var body: some View {
        ZStack {
            Circle()
                .fill(activity.tint.opacity(0.25))
                .frame(width: 18, height: 18)
                .scaleEffect(isExpanded ? 1.12 : 0.86)

            Circle()
                .fill(activity.tint)
                .frame(width: 7, height: 7)
        }
        .frame(width: 20, height: 20)
        .animation(animation, value: isExpanded)
        .task(id: animates) {
            isExpanded = animates
        }
        .accessibilityHidden(true)
    }

    private var animates: Bool {
        activity.pulses
            && RelayAccessibilityContract.allowsLoopingStatusMotion(
                reduceMotion: reduceMotion
            )
    }

    private var animation: Animation? {
        guard animates else { return nil }
        return .easeInOut(duration: activity.pulsePeriod).repeatForever(
            autoreverses: true
        )
    }
}
