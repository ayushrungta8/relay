# Requirement 5: Conversational control

## Outcome

The user can ask Relay about tasks and act on them using text or hold-to-talk.

## Required behavior

- Preserve the existing composer and Option-Space push-to-talk shortcut.
- Extend the controller tools with account-capacity and attention-inbox reads.
- Let requests such as “what happened with this one?”, “which tasks need me?”,
  and “how much usage is left?” use current monitored state.
- Resolve “this one” from the selected task first, then the most recently
  interacted task; ask a concise clarification when neither exists.
- Keep destructive actions explicit: interrupt only on a direct stop/cancel
  instruction.
- Stream or progressively display the controller answer when the app-server
  provides deltas.
- Keep task cards actionable while the controller is answering.
- Surface voice permission, capture, transcription, controller, and network
  failures as distinct recoverable states.

## Acceptance

Text and voice produce the same command semantics. Answers reference current
task and capacity state, ambiguous references do not target arbitrary tasks,
and failures explain the failed layer with a retry path.
