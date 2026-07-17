import RelayCore
import SwiftUI

struct RelayResetCreditDetailsView: View {
    let credits: [RelayRateLimitResetCredit]?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                if let credits, !credits.isEmpty {
                    creditRows(credits)
                } else {
                    Text("Credit expiry details unavailable")
                        .font(.caption)
                        .foregroundStyle(RelayPalette.secondaryText)
                        .padding(.horizontal, 16)
                        .frame(height: rowHeight)
                }
            }
        }
        .scrollIndicators(creditCount > maximumVisibleRows ? .automatic : .never)
        .frame(height: detailsHeight)
        .accessibilityElement(children: .contain)
    }

    @ViewBuilder
    private func creditRows(_ credits: [RelayRateLimitResetCredit]) -> some View {
        ForEach(credits, id: \.id) { credit in
            HStack(spacing: 12) {
                Text(creditTitle(credit.title))
                    .foregroundStyle(RelayPalette.primaryText)
                    .lineLimit(1)

                Spacer(minLength: 12)

                Text(expiryCopy(credit.expiresAt))
                    .foregroundStyle(RelayPalette.secondaryText)
                    .monospacedDigit()
                    .lineLimit(1)
            }
            .font(.caption)
            .padding(.horizontal, 16)
            .frame(height: rowHeight)

            if credit.id != credits.last?.id {
                Divider()
                    .overlay(RelayPalette.hairline)
                    .padding(.leading, 16)
            }
        }
    }

    private let rowHeight: CGFloat = 27
    private let maximumVisibleRows = 1

    private var creditCount: Int {
        max(credits?.count ?? 0, 1)
    }

    private var detailsHeight: CGFloat {
        CGFloat(min(creditCount, maximumVisibleRows)) * rowHeight
    }

    private func creditTitle(_ title: String?) -> String {
        let title = title?.trimmingCharacters(in: .whitespacesAndNewlines)
        if let title, !title.isEmpty {
            return title
        }
        return "Reset credit"
    }

    private func expiryCopy(_ expiresAt: Int64?) -> String {
        guard let expiresAt else { return "Expiry unavailable" }
        let date = Date(timeIntervalSince1970: TimeInterval(expiresAt))
        return "Expires \(RelayCapacityPresentation.timestampLabel(for: date))"
    }
}
