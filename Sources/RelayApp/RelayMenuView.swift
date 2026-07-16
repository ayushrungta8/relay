import AppKit
import RelayCore
import SwiftUI

struct RelayMenuView: View {
    let model: RelayAppModel

    var body: some View {
        @Bindable var model = model

        VStack(spacing: 0) {
            header
            Divider()
            RelayCommandComposerView(
                text: $model.commandText,
                phase: model.composerPhase
            ) {
                Task { await model.submitCommand() }
            }
            Divider()
            if model.latestResponse != nil {
                responsePanel
                Divider()
            }
            content
            Divider()
            footer
        }
        .frame(width: 420, height: 600)
        .background(Color(nsColor: .windowBackgroundColor))
        .tint(RelayPalette.accent)
        .task {
            await model.start()
            guard model.state == .idle else { return }
            await model.refresh()
        }
    }

    private var header: some View {
        HStack(spacing: 12) {
            Image(systemName: "arrow.left.arrow.right")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 34, height: 34)
                .background(RelayPalette.accent, in: .rect(cornerRadius: 9))
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 2) {
                Text("Relay")
                    .font(.headline)
                Text(headerSubtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer(minLength: 12)

            if model.state == .loading {
                ProgressView()
                    .controlSize(.small)
                    .accessibilityLabel("Refreshing Codex tasks")
            } else {
                Button {
                    Task { await model.refresh() }
                } label: {
                    Image(systemName: "arrow.clockwise")
                        .frame(width: 26, height: 26)
                }
                .buttonStyle(.borderless)
                .help("Refresh Codex tasks")
                .accessibilityLabel("Refresh Codex tasks")
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
    }

    @ViewBuilder
    private var content: some View {
        if model.state == .loading, model.threads.isEmpty {
            RelayLoadingView()
        } else if model.state == .failed, model.threads.isEmpty {
            RelayErrorView(
                message: model.errorMessage ?? "Relay could not reach Codex."
            ) {
                Task { await model.refresh() }
            }
        } else if model.threads.isEmpty {
            ContentUnavailableView {
                Label("No Codex tasks yet", systemImage: "tray")
            } description: {
                Text("Ask Relay above, or start a task directly in Codex.")
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            VStack(spacing: 0) {
                HStack {
                    Text("Codex tasks")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text("Active first")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 8)

                ScrollView {
                    LazyVStack(spacing: 2) {
                        ForEach(model.threads) { thread in
                            RelayThreadRow(thread: thread) {
                                open(thread)
                            }
                        }
                    }
                    .padding(.horizontal, 8)
                    .padding(.bottom, 8)
                }
            }
        }
    }

    private var responsePanel: some View {
        VStack(alignment: .leading, spacing: 7) {
            Label("Relay", systemImage: "sparkles")
                .font(.caption.weight(.semibold))
                .foregroundStyle(RelayPalette.accent)

            Text(model.latestResponse ?? "")
                .font(.callout)
                .lineLimit(5)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(RelayPalette.hoverSurface.opacity(0.7))
    }

    private var footer: some View {
        HStack(spacing: 8) {
            Button("Open Codex", systemImage: "arrow.up.forward.app") {
                openCodex()
            }
            .buttonStyle(.borderless)

            Spacer()

            if model.isVoiceActive {
                Button("Cancel voice") {
                    Task { await model.cancelVoice() }
                }
                .buttonStyle(.borderless)
                .keyboardShortcut(.cancelAction)
            } else {
                Text("Hold ⌥ Space to talk")
                    .foregroundStyle(.secondary)
            }

            Button("Quit") {
                NSApplication.shared.terminate(nil)
            }
            .buttonStyle(.borderless)
            .keyboardShortcut("q")
        }
        .font(.caption)
        .padding(.horizontal, 14)
        .frame(height: 42)
        .background(Color(nsColor: .controlBackgroundColor).opacity(0.55))
    }

    private var headerSubtitle: String {
        switch model.state {
        case .idle:
            "Your Codex controller"
        case .loading:
            "Reading Codex…"
        case .loaded:
            "\(model.threads.count) recent \(model.threads.count == 1 ? "task" : "tasks")"
        case .failed:
            "Codex is unavailable"
        }
    }

    private func open(_ thread: CodexThread) {
        guard let url = CodexDeepLink.thread(id: thread.id) else { return }
        NSWorkspace.shared.open(url)
    }

    private func openCodex() {
        guard let appURL = NSWorkspace.shared.urlForApplication(
            withBundleIdentifier: "com.openai.codex"
        ) else {
            return
        }
        NSWorkspace.shared.open(appURL)
    }
}
