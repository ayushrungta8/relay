import SwiftUI

struct RelayOrphanedDraftsView: View {
    let drafts: RelayPanelDraftStore

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            Label(
                "Unsaved draft needs attention",
                systemImage: "exclamationmark.bubble"
            )
            .font(.callout.bold())
            .accessibilityAddTraits(.isHeader)

            Text(
                "Its task or request is no longer visible. Cancel the draft before closing Relay."
            )
            .font(.caption)
            .foregroundStyle(RelayPalette.secondaryText)

            ForEach(drafts.orphanedDrafts) { orphan in
                Button(
                    cancelLabel(for: orphan),
                    systemImage: "xmark",
                    action: { discard(orphan) }
                )
                .buttonStyle(.bordered)
                .accessibilityHint(
                    "Discards the unsaved draft and allows Relay to close."
                )
            }
        }
        .padding(12)
        .background(
            RelayPalette.elevatedSurface,
            in: .rect(cornerRadius: 10)
        )
    }

    private func cancelLabel(for orphan: RelayOrphanedDraft) -> String {
        switch orphan.kind {
        case .pendingAnswer:
            "Cancel unsaved answer"
        case .followUp:
            "Cancel unsaved follow-up"
        }
    }

    private func discard(_ orphan: RelayOrphanedDraft) {
        drafts.discard(orphan)
    }
}
