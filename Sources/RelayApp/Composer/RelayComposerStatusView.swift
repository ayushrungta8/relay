import SwiftUI

struct RelayComposerStatusView: View {
    let phase: RelayComposerPhase

    var body: some View {
        switch phase {
        case .idle:
            EmptyView()
        case .listening:
            Label("Listening…", systemImage: "mic.fill")
                .foregroundStyle(.secondary)
        case .sending:
            Label {
                Text("Sending…")
            } icon: {
                ProgressView()
                    .controlSize(.small)
                    .accessibilityHidden(true)
            }
            .foregroundStyle(.secondary)
        case let .failed(message):
            Label(message, systemImage: "exclamationmark.triangle.fill")
                .foregroundStyle(.red)
        }
    }
}
