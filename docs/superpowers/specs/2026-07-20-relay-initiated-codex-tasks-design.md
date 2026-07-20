# Relay-Initiated Codex Tasks

## Goal

Relay should accept a request to do new work, create an ordinary visible Codex
worker task for that request, and immediately return to its normal role as a
responsive activity center and conversational liaison.

This is delegation, not a new orchestration subsystem. Relay does not retain a
blocking controller turn, create a separate job model, or continuously manage
the worker. Once created, the task uses Relay's existing monitoring,
attention, follow-up, interruption, and completion flows.

## User Flow

1. The user asks Relay to perform work by text or voice.
2. Relay inspects current task context and resolves the relevant project
   working directory.
3. Relay starts a normal Codex worker task with a complete prompt and that
   absolute working-directory path.
4. Relay replies with a short handoff confirmation identifying the new task.
5. The controller turn ends, leaving Relay immediately available for other
   requests.
6. The new worker appears and behaves like every other task in Relay.

If an existing worker already owns the same work, Relay sends the request to
that task instead of creating a duplicate.

## Project Path Resolution

Relay resolves the worker's `cwd` in this order:

1. The selected task's project path when the request refers to the selected
   task or its project.
2. A uniquely matching project path from recent visible tasks when the user
   names or clearly refers to that project.
3. The controller's configured workspace root when it is the only clear
   workspace for the request.
4. A concise clarification question when more than one path remains plausible.

Relay must use an absolute existing directory and must never invent a path.
An invalid or unresolved path prevents task creation and produces a clear,
recoverable response.

## Existing Architecture

The implementation should extend the current seams rather than add a new
coordinator:

- `relay_start_task` remains the controller tool for creating work.
- `relay_send_to_task` remains the duplicate-avoidance and follow-up path.
- `CodexTaskOperationsClient.startTask` continues to create a persistent,
  workspace-write Codex thread and start its first turn.
- The persistent Relay controller remains read-only and separate from worker
  threads.
- Relay's activity store continues to discover and supervise the new thread
  through the ordinary Codex task stream.

The controller instructions should make the path-resolution order and the
non-blocking handoff explicit. The tool boundary should validate that the path
is an absolute existing directory before starting a worker.

## Failure Handling

- If the request is ambiguous about its project, Relay asks one short path or
  project question and does not create a task yet.
- If task creation fails, Relay reports the failure and remains available; it
  does not claim that work started.
- If the worker later needs input, fails, or completes, existing Relay
  attention behavior applies without special orchestration state.
- Stop and cancel behavior remains explicit and continues through
  `relay_interrupt_task`.

## Product Language

Relay remains an activity center and conversational controller rather than a
second full Codex client. Product copy may say that Relay can delegate new work
to Codex, but should not imply autonomous planning, multi-agent coordination,
or continuous outcome management.

## Verification

Focused tests should prove that:

- a work request starts one worker with the intended prompt and absolute path;
- selected-task and uniquely matched recent-project paths are preferred;
- ambiguous or invalid paths ask for clarification instead of starting work;
- matching existing work is steered rather than duplicated;
- a successful handoff returns a concise answer and leaves the controller
  ready for the next command;
- the created worker appears through the normal monitoring path; and
- failures never produce a false success acknowledgement.
