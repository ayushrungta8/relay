# Codex Realtime Transcription Probe Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build and run a deterministic probe that streams generated PCM audio to the Codex app server and verifies that Codex returns the expected final transcript.

**Architecture:** A standalone Python standard-library script will generate speech with macOS `say`, convert it with `afconvert`, launch the installed Codex app server over JSONL stdio, create an ephemeral thread, and use the experimental thread realtime methods. Focused unit tests will cover audio chunk metadata, transcript matching, executable discovery, and JSON-RPC notification handling; the final step is a live service probe.

**Tech Stack:** Python 3 standard library, macOS `say`, macOS `afconvert`, Codex CLI app-server JSON-RPC, `unittest`.

## Global Constraints

- The probe must remain isolated under `scripts/` and must not replace Relay's Apple Speech implementation.
- Use only operating-system tools and Python standard-library modules.
- Use generated audio saying “Relay Codex speech transcription feasibility test.”
- Use mono PCM16 audio at 24,000 Hz.
- A pass requires a final user transcript containing `Relay`, `Codex`, `speech`, `transcription`, and `test`, ignoring case and punctuation.
- Temporary audio files and the app-server process must be cleaned up on every exit path.
- The Codex thread must be ephemeral so the probe does not leave a persisted task behind.

---

### Task 1: Build and run the deterministic transcription probe

**Files:**
- Create: `scripts/codex_realtime_stt_probe.py`
- Create: `Tests/ProbeTests/test_codex_realtime_stt_probe.py`

**Interfaces:**
- Consumes: `/Applications/ChatGPT.app/Contents/Resources/codex`, `say`, and `afconvert`.
- Produces: `find_codex_executable() -> pathlib.Path`, `pcm_chunks(data: bytes, frames_per_chunk: int = 4800) -> Iterator[dict[str, object]]`, `transcript_matches(text: str) -> bool`, `JsonRpcSession`, and a command-line program that exits `0` on `PASS` and non-zero on `FAIL`.

- [ ] **Step 1: Write failing unit tests for executable discovery, PCM metadata, transcript matching, and notification capture**

```python
from __future__ import annotations

import importlib.util
import io
import json
import pathlib
import unittest
from unittest import mock


SCRIPT = (
    pathlib.Path(__file__).parents[2]
    / "scripts"
    / "codex_realtime_stt_probe.py"
)
SPEC = importlib.util.spec_from_file_location("codex_stt_probe", SCRIPT)
assert SPEC is not None and SPEC.loader is not None
probe = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(probe)


class FakeProcess:
    def __init__(self, messages: list[dict[str, object]]) -> None:
        self.stdin = io.StringIO()
        self.stdout = io.StringIO(
            "".join(json.dumps(message) + "\n" for message in messages)
        )
        self.stderr = io.StringIO()


class CodexRealtimeProbeTests(unittest.TestCase):
    def test_find_codex_prefers_bundled_desktop_executable(self) -> None:
        bundled = pathlib.Path(
            "/Applications/ChatGPT.app/Contents/Resources/codex"
        )
        with mock.patch.object(pathlib.Path, "is_file", return_value=True):
            self.assertEqual(probe.find_codex_executable(), bundled)

    def test_pcm_chunks_emit_pcm16_mono_metadata(self) -> None:
        chunks = list(probe.pcm_chunks(b"\x01\x02" * 5, frames_per_chunk=3))
        self.assertEqual(len(chunks), 2)
        self.assertEqual(chunks[0]["sampleRate"], 24_000)
        self.assertEqual(chunks[0]["numChannels"], 1)
        self.assertEqual(chunks[0]["samplesPerChannel"], 3)
        self.assertEqual(chunks[1]["samplesPerChannel"], 2)

    def test_pcm_chunks_reject_odd_byte_count(self) -> None:
        with self.assertRaisesRegex(ValueError, "PCM16"):
            list(probe.pcm_chunks(b"\x00"))

    def test_transcript_match_ignores_case_and_punctuation(self) -> None:
        self.assertTrue(
            probe.transcript_matches(
                "Relay, CODEX speech-transcription feasibility test!"
            )
        )
        self.assertFalse(probe.transcript_matches("Relay audio probe"))

    def test_request_captures_notifications_before_response(self) -> None:
        process = FakeProcess(
            [
                {
                    "method": "thread/realtime/transcript/done",
                    "params": {
                        "threadId": "thread-1",
                        "role": "user",
                        "text": "Relay Codex speech transcription feasibility test.",
                    },
                },
                {"id": 1, "result": {}},
            ]
        )
        session = probe.JsonRpcSession(process)
        self.assertEqual(session.request("initialize", {}), {})
        self.assertEqual(
            session.notifications[0]["method"],
            "thread/realtime/transcript/done",
        )


if __name__ == "__main__":
    unittest.main()
```

- [ ] **Step 2: Run the unit tests and verify that the missing script causes failure**

Run:

```bash
python3 -m unittest discover -s Tests/ProbeTests -v
```

Expected: `ERROR` while importing `scripts/codex_realtime_stt_probe.py` because the file does not exist.

- [ ] **Step 3: Implement the probe with standard-library JSON-RPC and deterministic audio generation**

Create `scripts/codex_realtime_stt_probe.py` with these concrete components:

```python
#!/usr/bin/env python3
from __future__ import annotations

import argparse
import base64
import json
import os
import pathlib
import queue
import re
import shutil
import subprocess
import sys
import tempfile
import threading
import time
import wave
from collections.abc import Iterator
from typing import Any, TextIO


PHRASE = "Relay Codex speech transcription feasibility test."
EXPECTED_TERMS = {"relay", "codex", "speech", "transcription", "test"}
SAMPLE_RATE = 24_000
CHANNELS = 1
SAMPLE_WIDTH = 2
DEFAULT_CHUNK_FRAMES = 4_800
DESKTOP_CODEX = pathlib.Path(
    "/Applications/ChatGPT.app/Contents/Resources/codex"
)


def find_codex_executable() -> pathlib.Path:
    if DESKTOP_CODEX.is_file():
        return DESKTOP_CODEX
    located = shutil.which("codex")
    if located:
        return pathlib.Path(located)
    raise FileNotFoundError(
        "Codex executable was not found in the desktop app or PATH."
    )


def pcm_chunks(
    data: bytes,
    frames_per_chunk: int = DEFAULT_CHUNK_FRAMES,
) -> Iterator[dict[str, object]]:
    if len(data) % SAMPLE_WIDTH != 0:
        raise ValueError("PCM16 data must contain complete 16-bit samples.")
    bytes_per_chunk = frames_per_chunk * SAMPLE_WIDTH * CHANNELS
    for offset in range(0, len(data), bytes_per_chunk):
        chunk = data[offset : offset + bytes_per_chunk]
        frames = len(chunk) // (SAMPLE_WIDTH * CHANNELS)
        yield {
            "data": base64.b64encode(chunk).decode("ascii"),
            "sampleRate": SAMPLE_RATE,
            "numChannels": CHANNELS,
            "samplesPerChannel": frames,
        }


def transcript_matches(text: str) -> bool:
    words = set(re.findall(r"[a-z0-9]+", text.casefold()))
    return EXPECTED_TERMS <= words


class JsonRpcSession:
    def __init__(self, process: Any) -> None:
        self.process = process
        self.stdin: TextIO = process.stdin
        self.stdout: TextIO = process.stdout
        self.notifications: list[dict[str, Any]] = []
        self.next_id = 1
        self.incoming: queue.Queue[dict[str, Any] | BaseException | None] = (
            queue.Queue()
        )
        self.reader = threading.Thread(
            target=self._read_loop,
            name="codex-stt-probe-reader",
            daemon=True,
        )
        self.reader.start()

    def send(self, payload: dict[str, Any]) -> None:
        self.stdin.write(json.dumps(payload, separators=(",", ":")) + "\n")
        self.stdin.flush()

    def notify(self, method: str, params: dict[str, Any] | None = None) -> None:
        payload: dict[str, Any] = {"method": method}
        if params is not None:
            payload["params"] = params
        self.send(payload)

    def request(
        self,
        method: str,
        params: dict[str, Any],
        timeout_seconds: float = 30.0,
    ) -> dict[str, Any]:
        request_id = self.next_id
        self.next_id += 1
        self.send({"id": request_id, "method": method, "params": params})
        deadline = time.monotonic() + timeout_seconds
        while True:
            remaining = deadline - time.monotonic()
            if remaining <= 0:
                raise TimeoutError(f"Timed out waiting for {method}.")
            message = self.read_message(remaining)
            if message.get("id") != request_id:
                self.notifications.append(message)
                continue
            if "error" in message:
                raise RuntimeError(f"{method} failed: {message['error']}")
            result = message.get("result", {})
            if not isinstance(result, dict):
                raise RuntimeError(f"{method} returned a non-object result.")
            return result

    def _read_loop(self) -> None:
        try:
            for line in self.stdout:
                message = json.loads(line)
                if not isinstance(message, dict):
                    raise RuntimeError(
                        "Codex emitted a non-object JSON-RPC message."
                    )
                self.incoming.put(message)
        except BaseException as error:
            self.incoming.put(error)
        finally:
            self.incoming.put(None)

    def read_message(self, timeout_seconds: float) -> dict[str, Any]:
        try:
            item = self.incoming.get(timeout=timeout_seconds)
        except queue.Empty as error:
            raise TimeoutError("Timed out waiting for Codex output.") from error
        if isinstance(item, BaseException):
            raise RuntimeError(f"Could not read Codex output: {item}") from item
        if item is None:
            stderr = self.process.stderr.read().strip()
            detail = f": {stderr}" if stderr else ""
            raise RuntimeError(f"Codex app server closed unexpectedly{detail}")
        return item

    def wait_for_notification(
        self,
        method: str,
        thread_id: str,
        timeout_seconds: float,
    ) -> dict[str, Any]:
        deadline = time.monotonic() + timeout_seconds
        while True:
            for index, message in enumerate(self.notifications):
                params = message.get("params", {})
                if (
                    message.get("method") == method
                    and isinstance(params, dict)
                    and params.get("threadId") == thread_id
                ):
                    return self.notifications.pop(index)
            if time.monotonic() >= deadline:
                raise TimeoutError(f"Timed out waiting for {method}.")
            message = self.read_message(deadline - time.monotonic())
            if message.get("method") == "thread/realtime/error":
                params = message.get("params", {})
                raise RuntimeError(
                    f"Codex realtime error: {params.get('message', params)}"
                )
            self.notifications.append(message)


def generate_pcm(directory: pathlib.Path) -> bytes:
    source = directory / "source.aiff"
    output = directory / "probe.wav"
    subprocess.run(["say", "-o", str(source), PHRASE], check=True)
    subprocess.run(
        [
            "afconvert",
            "-f",
            "WAVE",
            "-d",
            "LEI16@24000",
            "-c",
            "1",
            str(source),
            str(output),
        ],
        check=True,
    )
    with wave.open(str(output), "rb") as audio:
        if (
            audio.getframerate() != SAMPLE_RATE
            or audio.getnchannels() != CHANNELS
            or audio.getsampwidth() != SAMPLE_WIDTH
        ):
            raise RuntimeError("Converted audio is not mono PCM16 at 24 kHz.")
        frames = audio.readframes(audio.getnframes())
    return frames + (b"\x00\x00" * SAMPLE_RATE)


def run_probe(timeout_seconds: float) -> str:
    executable = find_codex_executable()
    process = subprocess.Popen(
        [str(executable), "app-server", "--stdio"],
        stdin=subprocess.PIPE,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        bufsize=1,
    )
    assert process.stdin is not None
    assert process.stdout is not None
    assert process.stderr is not None
    session = JsonRpcSession(process)
    thread_id: str | None = None
    realtime_started = False
    try:
        session.request(
            "initialize",
            {
                "clientInfo": {
                    "name": "relay-stt-probe",
                    "title": "Relay STT Probe",
                    "version": "0.1.0",
                },
                "capabilities": {"experimentalApi": True},
            },
        )
        session.notify("initialized")
        thread_result = session.request(
            "thread/start",
            {
                "cwd": os.getcwd(),
                "ephemeral": True,
                "approvalPolicy": "never",
                "sandbox": "read-only",
            },
        )
        thread = thread_result.get("thread", {})
        thread_id = thread.get("id") if isinstance(thread, dict) else None
        if not thread_id:
            raise RuntimeError("thread/start did not return a thread id.")
        session.request(
            "thread/realtime/start",
            {
                "threadId": thread_id,
                "outputModality": "text",
                "transport": {"type": "websocket"},
                "version": "v2",
                "includeStartupContext": False,
                "clientManagedHandoffs": True,
                "flushTranscriptTailOnSessionEnd": True,
            },
        )
        session.wait_for_notification(
            "thread/realtime/started", thread_id, timeout_seconds
        )
        realtime_started = True
        with tempfile.TemporaryDirectory(prefix="relay-codex-stt-") as raw:
            pcm = generate_pcm(pathlib.Path(raw))
            for audio in pcm_chunks(pcm):
                session.request(
                    "thread/realtime/appendAudio",
                    {"threadId": thread_id, "audio": audio},
                )
        session.request("thread/realtime/stop", {"threadId": thread_id})
        realtime_started = False
        done = session.wait_for_notification(
            "thread/realtime/transcript/done",
            thread_id,
            timeout_seconds,
        )
        params = done.get("params", {})
        text = params.get("text", "") if isinstance(params, dict) else ""
        if not isinstance(text, str) or not text.strip():
            raise RuntimeError("Codex returned an empty final transcript.")
        return text.strip()
    finally:
        if realtime_started and thread_id:
            try:
                session.request(
                    "thread/realtime/stop", {"threadId": thread_id}
                )
            except Exception:
                pass
        process.terminate()
        try:
            process.wait(timeout=3)
        except subprocess.TimeoutExpired:
            process.kill()
            process.wait(timeout=3)


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--timeout", type=float, default=30.0)
    args = parser.parse_args()
    try:
        transcript = run_probe(args.timeout)
    except Exception as error:
        print(f"FAIL: {error}", file=sys.stderr)
        return 1
    if not transcript_matches(transcript):
        print(f"FAIL: transcript did not match expected terms: {transcript}")
        return 2
    print(f"PASS: {transcript}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
```

- [ ] **Step 4: Run the focused unit tests and verify they pass**

Run:

```bash
python3 -m unittest discover -s Tests/ProbeTests -v
```

Expected: five tests run and all report `ok`.

- [ ] **Step 5: Run static syntax validation**

Run:

```bash
python3 -m py_compile scripts/codex_realtime_stt_probe.py Tests/ProbeTests/test_codex_realtime_stt_probe.py
```

Expected: exit status `0` with no output.

- [ ] **Step 6: Run the live Codex transcription probe**

Run:

```bash
python3 scripts/codex_realtime_stt_probe.py --timeout 30
```

Expected success shape:

```text
PASS: Relay Codex speech transcription feasibility test.
```

If Codex returns a protocol, authentication, availability, or transcript error, preserve the exact `FAIL:` output as the feasibility result and diagnose only issues inside the probe's approved scope.

- [ ] **Step 7: Re-run all repository tests to ensure the isolated probe caused no regression**

Run:

```bash
swift test
```

Expected: all existing Swift tests pass.

- [ ] **Step 8: Commit the probe and its tests**

```bash
git add scripts/codex_realtime_stt_probe.py Tests/ProbeTests/test_codex_realtime_stt_probe.py
git commit -m "test: probe Codex realtime transcription"
```
