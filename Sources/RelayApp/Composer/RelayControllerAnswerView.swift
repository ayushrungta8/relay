import SwiftUI

struct RelayControllerAnswerView: View {
    let answer: String

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Label("Relay answer", systemImage: "sparkles")
                .font(.callout)
                .bold()
                .foregroundStyle(RelayPalette.secondaryText)

            Text(answer)
                .font(.body)
                .foregroundStyle(RelayPalette.primaryText)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Relay answer: \(answer)")
    }
}
