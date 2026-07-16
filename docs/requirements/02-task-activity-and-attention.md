# Requirement 2: Task activity and attention

## Outcome

Relay answers three questions immediately: what needs me, what is running, and
what finished since I last looked.

## Required behavior

- Decode Codex thread active flags `waitingOnApproval` and
  `waitingOnUserInput`.
- Normalize thread state to `needsInput`, `failed`, `ready`, `running`, and
  `idle`, in that priority order.
- Show the latest meaningful progress item from agent messages, plans, command
  execution, or errors.
- Track unread completion/failure activity locally and clear it when the user
  opens the task or marks it read.
- Keep the controller thread hidden.
- Group the expanded interface into Attention, Running, and Recent sections.
- Keep compact mode to a small horizontal tray ordered by priority and recency.
- Provide Open in Codex, Send follow-up, Interrupt, and Mark read actions where
  valid.
- Never infer percentage progress when Codex has not supplied one.

## Acceptance

A waiting task is always ranked above a merely running task. A newly completed
task remains visible as ready until acknowledged. Every card has a plain-language
state label and a useful latest update or an honest fallback.
