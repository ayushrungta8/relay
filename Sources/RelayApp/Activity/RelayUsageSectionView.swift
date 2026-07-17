import RelayCore
import SwiftUI

struct RelayUsageActions {
    let applyResetCredit: (String) async throws -> Void
    let setAutoApplyResetCredits: (Bool) -> Void
}

struct RelayUsageSectionView: View {
    let capacity: RelayCapacityPresentation
    let autoApplyResetCredits: Bool
    let actions: RelayUsageActions

    @State private var confirmingCreditID: String?
    @State private var applyingCreditID: String?
    @State private var errorMessage: String?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                windowsSection

                creditsSection

                autoApplySection

                if let errorMessage {
                    Text(errorMessage)
                        .font(.caption)
                        .foregroundStyle(RelayPalette.failed)
                }
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .scrollIndicators(.automatic)
        .background(RelayPalette.detailSurface)
    }

    @ViewBuilder
    private var windowsSection: some View {
        if capacity.windows.isEmpty {
            Label(
                "Codex did not provide account usage.",
                systemImage: "eye.slash"
            )
            .font(.callout)
            .foregroundStyle(RelayPalette.secondaryText)
        } else {
            ForEach(capacity.windows) { window in
                VStack(alignment: .leading, spacing: 7) {
                    HStack {
                        Text(window.label)
                            .font(.callout)
                            .bold()
                            .foregroundStyle(RelayPalette.primaryText)

                        Spacer()

                        Text("\(window.usedPercent)%")
                            .font(.callout)
                            .monospacedDigit()
                            .foregroundStyle(RelayPalette.primaryText)
                    }

                    ProgressView(value: window.progress)
                        .progressViewStyle(.linear)
                        .tint(levelColor(window.level))
                        .accessibilityLabel(window.label)
                        .accessibilityValue(
                            "\(window.usedPercent) percent used"
                        )

                    if let resetDate = window.resetDate {
                        Label(
                            "Resets \(RelayCapacityPresentation.timestampLabel(for: resetDate))",
                            systemImage: "clock.arrow.circlepath"
                        )
                        .font(.caption)
                        .foregroundStyle(RelayPalette.secondaryText)
                    }
                }
            }
        }
    }

    private var creditsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(capacity.resetCreditsCopy)
                .font(.caption)
                .foregroundStyle(RelayPalette.secondaryText)

            if let credits = sortedCredits, !credits.isEmpty {
                VStack(spacing: 0) {
                    ForEach(credits, id: \.id) { credit in
                        creditRow(credit)

                        if credit.id != credits.last?.id {
                            Divider().overlay(RelayPalette.hairline)
                        }
                    }
                }
                .background(RelayPalette.elevatedSurface)
                .clipShape(.rect(cornerRadius: 8))
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(RelayPalette.hairline, lineWidth: 1)
                )
            }
        }
    }

    private func creditRow(
        _ credit: RelayRateLimitResetCredit
    ) -> some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(Self.creditTitle(credit.title))
                    .font(.callout)
                    .foregroundStyle(RelayPalette.primaryText)

                let expiry = Self.expiryCopy(
                    expiresAt: credit.expiresAt
                )
                Text(expiry.text)
                    .font(.caption)
                    .monospacedDigit()
                    .foregroundStyle(
                        expiry.isUrgent
                            ? RelayPalette.warning
                            : RelayPalette.secondaryText
                    )
            }

            Spacer(minLength: 12)

            creditAction(credit)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
    }

    @ViewBuilder
    private func creditAction(_ credit: RelayRateLimitResetCredit) -> some View {
        if credit.status == "available" {
            if applyingCreditID == credit.id {
                ProgressView()
                    .controlSize(.small)
            } else {
                Button(
                    confirmingCreditID == credit.id ? "Confirm?" : "Apply"
                ) {
                    creditActionTapped(credit)
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .tint(
                    confirmingCreditID == credit.id
                        ? RelayPalette.accent
                        : nil
                )
                .disabled(applyingCreditID != nil)
                .accessibilityHint(
                    confirmingCreditID == credit.id
                        ? "Confirms spending this reset credit"
                        : "Spends this reset credit to reset usage"
                )
            }
        } else {
            Text(Self.statusLabel(credit.status))
                .font(.caption)
                .foregroundStyle(RelayPalette.tertiaryText)
        }
    }

    private var autoApplySection: some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Apply credits automatically")
                    .font(.callout)
                    .foregroundStyle(RelayPalette.primaryText)

                Text("Uses a credit 1 hour before it expires so it isn't wasted.")
                    .font(.caption)
                    .foregroundStyle(RelayPalette.secondaryText)
            }

            Spacer(minLength: 12)

            Toggle(
                "Apply credits automatically",
                isOn: Binding(
                    get: { autoApplyResetCredits },
                    set: { actions.setAutoApplyResetCredits($0) }
                )
            )
            .labelsHidden()
            .toggleStyle(.switch)
            .controlSize(.small)
            .tint(RelayPalette.accent)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
        .background(RelayPalette.elevatedSurface)
        .clipShape(.rect(cornerRadius: 8))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(RelayPalette.hairline, lineWidth: 1)
        )
    }

    private var sortedCredits: [RelayRateLimitResetCredit]? {
        capacity.resetCredits?.sorted {
            ($0.expiresAt ?? .max) < ($1.expiresAt ?? .max)
        }
    }

    private func creditActionTapped(_ credit: RelayRateLimitResetCredit) {
        errorMessage = nil
        guard confirmingCreditID == credit.id else {
            confirmingCreditID = credit.id
            return
        }
        confirmingCreditID = nil
        applyingCreditID = credit.id
        Task {
            defer { applyingCreditID = nil }
            do {
                try await actions.applyResetCredit(credit.id)
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }

    private func levelColor(
        _ level: RelayCapacityPresentation.Level
    ) -> Color {
        switch level {
        case .standard: RelayPalette.ready
        case .warning: RelayPalette.warning
        case .critical: RelayPalette.critical
        }
    }

    static func creditTitle(_ title: String?) -> String {
        let title = title?.trimmingCharacters(in: .whitespacesAndNewlines)
        if let title, !title.isEmpty {
            return title
        }
        return "Reset credit"
    }

    static func statusLabel(_ status: String) -> String {
        switch status {
        case "redeemed": "Redeemed"
        case "redeeming": "Redeeming…"
        case "cooldown_active": "Cooling down"
        default: status.capitalized
        }
    }

    static func expiryCopy(
        expiresAt: Int64?,
        now: Date = .now
    ) -> (text: String, isUrgent: Bool) {
        guard let expiresAt else {
            return ("Expiry unavailable", false)
        }
        let date = Date(timeIntervalSince1970: TimeInterval(expiresAt))
        let timestamp = RelayCapacityPresentation.timestampLabel(for: date)
        let remaining = date.timeIntervalSince(now)
        guard remaining > 0 else {
            return ("Expired \(timestamp)", false)
        }
        guard remaining < 24 * 3_600 else {
            return ("Usable until \(timestamp)", false)
        }
        let hours = Int((remaining / 3_600).rounded(.up))
        let window = hours <= 1
            ? "less than an hour"
            : "\(hours) more hours"
        return ("Usable for \(window) · \(timestamp)", true)
    }
}
