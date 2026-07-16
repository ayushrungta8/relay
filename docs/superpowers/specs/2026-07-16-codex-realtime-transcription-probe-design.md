# Codex Realtime Transcription Probe

## Goal

Prove whether Relay can send deterministic audio to the Codex desktop
app's bundled app server and receive a final speech transcript through
its experimental realtime protocol.

The probe is successful when Codex returns a non-empty final transcript
that substantially matches the generated phrase:

> Relay Codex speech transcription feasibility test.

## Scope

This is an isolated feasibility probe. It will not replace Relay's
existing Apple Speech transcriber, change the application UI, capture
live microphone input, or submit the transcript as a Codex command.

## Approach

Add a standalone diagnostic script under `scripts/`. The script will:

1. Generate an audio file with the macOS `say` command.
2. Convert that file to mono PCM16 audio at a rate accepted by Codex.
3. Launch the Codex app server bundled with the installed desktop app.
4. Complete the app-server initialization handshake.
5. Create a temporary Codex thread for the probe.
6. Start a thread-scoped realtime session with text output.
7. Stream base64-encoded PCM chunks through
   `thread/realtime/appendAudio`.
8. Stop the realtime session and wait for
   `thread/realtime/transcript/done`.
9. Print a concise `PASS` result with the transcript, or `FAIL` with
   the protocol or service error.

The script will use only operating-system tools and standard-library
code so that the probe does not add a runtime dependency to Relay.

## Data Flow

Generated phrase → `say` audio file → PCM16 conversion → chunked
base64 audio → Codex app-server realtime session → transcript
notification → terminal result.

## Isolation and Cleanup

Temporary audio files will live in a temporary directory and will be
removed when the probe exits. The probe thread will have a recognizable
name so it can be identified. If the protocol supports deletion in the
installed Codex version, the script will delete the temporary thread
after collecting the result; otherwise it will report the retained
thread ID.

The probe must not modify Relay's production transcription path.

## Error Handling

The script will distinguish these failure classes:

- Codex executable not found.
- App-server initialization failure.
- Authentication or service-unavailable failure.
- Temporary thread creation failure.
- Realtime session start failure.
- Audio conversion or streaming failure.
- Timeout before a final transcript.
- Empty or materially incorrect transcript.

It will stop the realtime session and terminate the app-server process
on every exit path.

## Verification

Run the probe once against the installed Codex desktop build. A pass
requires:

- Successful initialization and realtime session startup.
- At least one final user transcript notification.
- A non-empty transcript containing the important words `Relay`,
  `Codex`, `speech`, `transcription`, and `test`, allowing punctuation
  and capitalization differences.

The implementation will also include a dry validation of audio format
and chunk metadata before sending any audio.

## Follow-up Decision

If the probe passes, the next design can replace
`AppleSpeechTranscriber` behind the existing `RelaySpeechTranscribing`
interface with a Codex-backed implementation. If it fails because the
experimental API is unavailable or unsuitable, Relay will keep the
Apple Speech path and the probe output will document the limiting
condition.
