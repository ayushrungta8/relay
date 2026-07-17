import SwiftUI

struct RelayControllerAnswerView: View {
    let answer: String

    var body: some View {
        ScrollView(.vertical) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Label("Relay", systemImage: "sparkles")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(RelayPalette.secondaryText)

                Text(answer)
                    .font(.caption)
                    .foregroundStyle(RelayPalette.primaryText)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
        }
        .scrollIndicators(.never)
        .background(RelayPalette.elevatedSurface.opacity(0.82))
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Relay answer: \(answer)")
    }
}
