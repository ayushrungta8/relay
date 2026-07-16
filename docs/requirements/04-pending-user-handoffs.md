# Requirement 4: Pending user handoffs

## Outcome

Relay reliably identifies tasks paused for the user and provides the fastest
safe path to resolve them.

## Required behavior

- Treat Codex active flags as the authoritative cross-client signal that a task
  is waiting on approval or user input.
- Preserve and present full question/option payloads when Relay owns the
  app-server request that created the pending interaction.
- Allow a single- or multi-question answer to be submitted through the original
  JSON-RPC request when Relay owns it.
- Allow approve/decline only with the exact decision values supported by the
  request type.
- For tasks whose pending request belongs to another Codex client connection,
  show the waiting state and open the exact task in Codex rather than pretending
  Relay can answer it.
- Never auto-decline worker requests merely to keep a Relay controller turn
  moving. Controller-only internal requests may retain the current safe decline
  policy.
- Automatic peeks prioritize waiting tasks over failures, ready tasks, and
  running updates.

## Acceptance

Relay never leaves an owned request hanging, never claims it resolved an
external request, and gives waiting tasks an unmistakable action. A user can
answer Relay-owned questions without opening Codex.
