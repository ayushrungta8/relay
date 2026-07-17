import SwiftUI

struct RelayCommandComposerView: View {
    @Binding var text: String
    let phase: RelayComposerPhase
    let submit: () -> Void

    @State private var submissionGate = RelayCommandSubmissionGate()
    @FocusState private var isFocused: Bool

    var body: some View {
        HStack(spacing: 8) {
            if phase != .idle {
                RelayComposerStatusView(phase: phase)
                    .font(.caption)
                    .lineLimit(1)
                    .frame(maxWidth: 116, alignment: .leading)
            }

            TextField(
                text: $text,
                prompt: Text("Ask Relay about these tasks…")
                    .foregroundStyle(RelayPalette.secondaryText)
            ) {
                EmptyView()
            }
                .textFieldStyle(.plain)
                .submitLabel(.send)
                .onSubmit(submitIfPossible)
                .disabled(isInputDisabled)
                .focused($isFocused)
                .accessibilityLabel(
                    RelayAccessibilityContract.commandFieldLabel
                )
                .padding(.leading, 5)
                .frame(maxWidth: .infinity)

            Button(
                RelayAccessibilityContract.sendCommandLabel,
                systemImage: "arrow.up",
                action: submitIfPossible
            )
            .labelStyle(.iconOnly)
            .buttonStyle(.plain)
            .foregroundStyle(
                canSubmit
                    ? RelayPalette.primaryText
                    : RelayPalette.tertiaryText
            )
            .frame(width: 36, height: 36)
            .background(
                canSubmit
                    ? RelayPalette.accent
                    : RelayPalette.elevatedSurface,
                in: .rect(cornerRadius: 10)
            )
            .shadow(
                color: RelayPalette.accent.opacity(canSubmit ? 0.28 : 0),
                radius: 7
            )
            .disabled(!canSubmit)
            .help("Send command")
            .accessibilityHint("Submits the current command")
            .keyboardShortcut(
                RelayAccessibilityContract.sendCommandKeyEquivalent,
                modifiers: []
            )
        }
        .padding(.leading, 8)
        .padding(.trailing, 6)
        .frame(height: 42)
        .background(
            RelayPalette.fieldSurface,
            in: .rect(cornerRadius: 14)
        )
        .overlay {
            RoundedRectangle(cornerRadius: 14)
                .stroke(
                    isFocused
                        ? RelayPalette.accent.opacity(0.72)
                        : RelayPalette.fieldBorder,
                    lineWidth: 1
                )
        }
        .shadow(
            color: RelayPalette.accent.opacity(isFocused ? 0.13 : 0),
            radius: 8
        )
        .controlSize(.regular)
        .padding(.horizontal, 13)
        .background(RelayPalette.shell)
        .onChange(of: phase) { _, newPhase in
            submissionGate.phaseDidChange(to: newPhase)
        }
    }

    private var canSubmit: Bool {
        submissionGate.canBeginSubmission(
            draft: RelayCommandDraft(text: text),
            phase: phase
        )
    }

    private var isInputDisabled: Bool {
        switch phase {
        case .idle, .failed:
            false
        case .listening, .sending:
            true
        }
    }

    private func submitIfPossible() {
        let draft = RelayCommandDraft(text: text)
        guard let submission = draft.normalizedSubmission else {
            return
        }
        guard submissionGate.beginSubmission(
            draft: draft,
            phase: phase
        ) else {
            return
        }

        text = submission
        submit()
    }
}
