import SwiftUI

struct RelayUpdateBanner: View {
    let presentation: RelayUpdatePresentation
    let canInstall: Bool
    let install: () -> Void
    let deferUpdate: () -> Void
    let retry: () -> Void
    let dismiss: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: symbolName)
                .foregroundStyle(symbolColor)
                .frame(width: 18)

            Text(message)
                .font(.callout)
                .foregroundStyle(RelayPalette.primaryText)
                .lineLimit(1)

            Spacer(minLength: 12)

            if case .downloading(_, let progress) = presentation,
               let progress {
                ProgressView(value: progress)
                    .progressViewStyle(.linear)
                    .frame(width: 92)
            }

            actions
        }
        .padding(.horizontal, 16)
        .frame(height: 40)
        .background(RelayPalette.elevatedSurface)
        .accessibilityElement(children: .contain)
    }

    @ViewBuilder
    private var actions: some View {
        switch presentation {
        case .available:
            Button("Later", action: deferUpdate)
                .buttonStyle(.plain)
                .foregroundStyle(RelayPalette.secondaryText)

            Button("Install & Relaunch", action: install)
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
                .disabled(!canInstall)
                .help(
                    canInstall
                        ? "Install the update and relaunch Relay"
                        : "Finish or discard unfinished work before updating"
                )
        case .failed:
            Button("Dismiss", action: dismiss)
                .buttonStyle(.plain)
                .foregroundStyle(RelayPalette.secondaryText)

            Button("Retry", action: retry)
                .buttonStyle(.bordered)
                .controlSize(.small)
        case .upToDate:
            Button("Dismiss", action: dismiss)
                .buttonStyle(.plain)
                .foregroundStyle(RelayPalette.secondaryText)
        case .idle, .checking, .downloading, .preparing:
            EmptyView()
        }
    }

    private var message: String {
        switch presentation {
        case .idle:
            ""
        case .checking:
            "Checking for Relay updates…"
        case let .available(version):
            "Relay \(version) is available"
        case let .downloading(version, _):
            "Downloading Relay \(version)…"
        case let .preparing(version):
            "Preparing Relay \(version)…"
        case .upToDate:
            "Relay is up to date"
        case let .failed(message):
            "Update failed: \(message)"
        }
    }

    private var symbolName: String {
        switch presentation {
        case .idle, .checking, .downloading, .preparing:
            "arrow.triangle.2.circlepath"
        case .available:
            "arrow.down.circle.fill"
        case .upToDate:
            "checkmark.circle.fill"
        case .failed:
            "exclamationmark.triangle.fill"
        }
    }

    private var symbolColor: Color {
        switch presentation {
        case .available:
            RelayPalette.accentHighlight
        case .upToDate:
            RelayPalette.ready
        case .failed:
            RelayPalette.failed
        case .idle, .checking, .downloading, .preparing:
            RelayPalette.secondaryText
        }
    }
}
