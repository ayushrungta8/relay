import SwiftUI

struct RelayConnectionStatusView: View {
    let presentation: RelayConnectionPresentation
    let retry: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Label(presentation.label, systemImage: "wifi.exclamationmark")
                .font(.callout)
                .foregroundStyle(RelayPalette.secondaryText)

            if let detail = presentation.detail {
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(RelayPalette.tertiaryText)
                    .lineLimit(2)
            }

            Spacer()

            if presentation.showsRetry {
                Button("Retry", systemImage: "arrow.clockwise", action: retry)
                    .buttonStyle(.bordered)
            }
        }
        .padding(10)
        .background(RelayPalette.elevatedSurface, in: .rect(cornerRadius: 10))
    }
}
