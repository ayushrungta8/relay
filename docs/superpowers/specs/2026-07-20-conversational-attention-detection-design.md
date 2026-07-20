# Conversational Attention Detection

## Goal

Relay should treat a completed Codex response that clearly waits for the user
as needing input even when Codex did not emit a structured question or
approval request. For example, “Please review the plan and reply approved”
should appear alongside other tasks that need the user.

The feature must preserve the distinction between a real app-server request
and an inferred conversational request. Inferred requests use an ordinary
follow-up turn; they must not be submitted through the question or approval
RPC response paths.

## Classification Strategy

Classification follows an ordered hybrid pipeline:

1. Codex `waitingOnApproval` and `waitingOnUserInput` flags remain
   authoritative and produce the existing structured `needsInput` behavior.
2. A deterministic local classifier handles high-confidence positives and
   negatives. Strong gating language such as “reply approved,” “confirm before
   I continue,” or “tell me when it is ready” is positive. Completed outcome
   summaries with no request are negative. A question mark alone is not a
   positive signal.
3. Only ambiguous completed final answers are sent to an AI classifier.

The AI classifier uses the same Codex app-server connection, authentication,
and account path as Relay Controller. It runs in a separate persistent thread
named `Relay Attention Classifier` so classification prompts cannot pollute the
controller conversation or contend with user commands. Relay filters this
internal thread from its activity UI. The task may remain visible in Codex's
own task list because app-server does not provide Relay with a private hidden
conversation primitive.

The initial implementation uses Relay Controller's existing default model,
`gpt-5.6-terra`, with low reasoning effort. The model choice remains an
internal configuration rather than a new user-facing setting.

The classifier receives only the latest final assistant message and a fixed
instruction defining a blocking request. It returns a small structured result:

```json
{
  "needs_reply": true,
  "confidence": "high",
  "reason": "explicit approval gate"
}
```

Only valid, high-confidence positive results promote a task. Invalid output,
timeouts, connection failures, and low-confidence results preserve the normal
completed-task behavior.

## Monitoring and State

The monitoring decoder will retain the latest turn ID, item phase, and the raw
final-answer text. Classification happens before the existing display
normalization truncates updates to 800 characters, because the user request is
commonly at the end of a long response.

`RelayTaskActivity` gains an attention reason independent from its visual
priority. At minimum the reasons distinguish:

- a structured Codex interaction;
- an inferred conversational reply request;
- an unread completion;
- a failure, running task, or idle task.

Both structured and inferred requests map to the existing highest-priority
`needsInput` state. The reason determines which controls and explanation Relay
shows.

Classification results are cached by latest turn ID and a hash of the final
message. Relay performs at most one AI classification for an unchanged turn.
When a new turn replaces it, the old classification is discarded naturally.

A dismissed inferred request is stored by thread ID and turn ID so periodic
snapshot refreshes and application restarts do not immediately recreate it.
Sending a follow-up also dismisses the classified turn before the new turn
starts. Dismissals use `UserDefaults` and retain the 200 most recent entries,
ordered by dismissal time, to keep persistence bounded. A newer turn is
evaluated independently.

## User Experience

An inferred request uses the same coral `needsInput` priority and contributes
to the compact “needs you” count. Its selected-task presentation says that
Codex is waiting for a reply and shows:

- an inline follow-up composer;
- Open in Codex;
- Dismiss.

It does not show approval buttons, structured answer choices, or the existing
“request belongs to another Codex client” explanation. Genuine server requests
continue through the existing pending-interaction UI without behavior changes.

## Runtime Flow

After a completed-turn notification, Relay refreshes the thread and extracts
the newest `final_answer` message. Structured flags are checked first. The
local classifier then returns positive, negative, or ambiguous. Ambiguous
messages enter a deduplicated asynchronous classification queue.

The task remains in its ordinary ready state while classification is in
flight. A positive result republishes activity with the inferred reason. A
negative or failed result is cached without changing the task. Classification
must never delay snapshots, block the event-consumption loop, or alter the
worker task being inspected.

The dedicated classifier session is serialized so multiple completed tasks do
not interleave turns. Results are associated with the originating thread and
turn before publication; stale results for superseded turns are ignored.

## Failure Handling

- If the classifier session cannot start or resume, Relay keeps the task
  `ready` and retries only after a later ambiguous turn or reconnect.
- If classification times out or returns malformed data, Relay records a
  negative cache entry for that turn to avoid a retry loop during one-second
  monitoring refreshes.
- If a result arrives after the worker has started a newer turn, Relay drops
  it.
- If the local classifier is confidently positive, Relay does not require AI
  availability.
- Structured Codex flags always override inferred and dismissed state.

## Verification

Focused tests will cover:

- explicit approval and reply gates classified locally;
- ordinary completion summaries remaining ready;
- generic question marks and non-blocking offers not being promoted locally;
- ambiguous text invoking AI exactly once per unchanged turn;
- valid positive, valid negative, malformed, timed-out, and stale AI results;
- inferred requests surviving refresh, clearing after reply, and staying
  dismissed across restart;
- structured pending interactions retaining their current presentation;
- inferred requests using the follow-up UI rather than RPC approval controls;
- controller and classifier threads remaining absent from Relay activity;
- classifier failure never blocking monitoring or changing the worker thread.

The final verification will run the focused classifier, reducer, monitoring,
and presentation tests followed by the full Swift test suite.
