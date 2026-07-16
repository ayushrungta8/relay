import SwiftUI

struct RelayCommandComposerView: View {
    @Binding var text: String
    let phase: RelayComposerPhase
    let submit: () -> Void

    @State private var submissionGate = RelayCommandSubmissionGate()

    var body: some View {
        VStack(alignment: .leading) {
            HStack {
                TextField("Ask Relay to do something…", text: $text)
                    .textFieldStyle(.roundedBorder)
                    .submitLabel(.send)
                    .onSubmit(submitIfPossible)
                    .disabled(isInputDisabled)

                Button(
                    "Send command",
                    systemImage: "arrow.up",
                    action: submitIfPossible
                )
                .labelStyle(.iconOnly)
                .buttonStyle(.borderedProminent)
                .disabled(!canSubmit)
                .help("Send command")
                .accessibilityHint("Submits the current command")
            }
            .controlSize(.large)

            if phase != .idle {
                RelayComposerStatusView(phase: phase)
                    .font(.caption)
                    .lineLimit(2)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding()
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
