import RelayCore
import SwiftUI

struct RelayPeekView: View {
    let copy: String
    let state: RelayTaskAttentionState

    var body: some View {
        HStack(spacing: 10) {
            RelayStatusSymbol(state: state)
                .labelStyle(.iconOnly)

            Text(copy)
                .font(.callout)
                .bold()
                .foregroundStyle(RelayPalette.primaryText)
                .lineLimit(1)
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(copy)
    }
}
