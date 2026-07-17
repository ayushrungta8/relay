import AppKit
import SwiftUI

struct RelayCapacityFooter: View {
    let presentation: RelayCapacityPresentation

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var showsCreditDetails = false

    var body: some View {
        VStack(spacing: 0) {
            RelayCapacityStrip(presentation: presentation)
                .frame(height: 51)

            Divider().overlay(RelayPalette.hairline)

            resetSummary
                .frame(height: 31)

            if showsCreditDetails {
                Divider().overlay(RelayPalette.hairline)

                RelayResetCreditDetailsView(
                    credits: presentation.resetCredits
                )
                .transition(
                    reduceMotion
                        ? .opacity
                        : .opacity.combined(with: .move(edge: .top))
                )
            }
        }
        .background(RelayPalette.railSurface)
        .animation(
            reduceMotion
                ? .linear(duration: 0.12)
                : .easeOut(duration: 0.18),
            value: showsCreditDetails
        )
    }

    private var resetSummary: some View {
        HStack(spacing: 8) {
            Label(resetTimeCopy, systemImage: "clock.arrow.circlepath")
                .lineLimit(1)

            Text("·")
                .accessibilityHidden(true)

            Button(action: toggleCreditDetails) {
                HStack(spacing: 5) {
                    Text(presentation.resetCreditsCopy)
                        .lineLimit(1)

                    if hasCreditDetails {
                        Image(
                            systemName: showsCreditDetails
                                ? "chevron.up"
                                : "chevron.down"
                        )
                        .font(.caption2.weight(.semibold))
                        .accessibilityHidden(true)
                    }
                }
                .contentShape(.rect)
            }
            .buttonStyle(.plain)
            .disabled(!hasCreditDetails)
            .onContinuousHover { phase in
                guard hasCreditDetails else { return }
                switch phase {
                case .active:
                    NSCursor.pointingHand.set()
                case .ended:
                    NSCursor.arrow.set()
                }
            }
            .accessibilityLabel(presentation.resetCreditsCopy)
            .accessibilityHint(
                showsCreditDetails
                    ? "Hides reset credit details"
                    : "Shows reset credit details"
            )

            Spacer(minLength: 0)
        }
        .font(.caption)
        .foregroundStyle(RelayPalette.secondaryText)
        .padding(.horizontal, 16)
        .accessibilityElement(children: .contain)
    }

    private var resetTimeCopy: String {
        guard let resetDate = presentation.nextResetDate else {
            return "Reset time unavailable"
        }
        return "Resets \(RelayCapacityPresentation.timestampLabel(for: resetDate))"
    }

    private var hasCreditDetails: Bool {
        !(presentation.resetCredits?.isEmpty ?? true)
    }

    private func toggleCreditDetails() {
        guard hasCreditDetails else { return }
        showsCreditDetails.toggle()
    }
}
