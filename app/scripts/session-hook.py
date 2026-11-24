"""Fail-open Claude/Codex/MLX lifecycle adapter. Emits only allowlisted metadata locally."""
from __future__ import annotations

import fcntl
import json
import os
from pathlib import Path
import re
import sys
import time
import uuid

EVENTS = frozenset({"SessionStart", "SessionEnd", "UserPromptSubmit", "PreToolUse",
                    "PostToolUse", "PostToolUseFailure", "PermissionRequest", "Stop",
                    "StopFailure", "Interrupt", "SubagentStart", "SubagentStop",
                    "PreModelRequest", "PostModelRequest"})


def identifier(value: object) -> str | None:
    if not isinstance(value, str) or not re.fullmatch(r"[A-Za-z0-9_.:/-]{1,128}", value):
        return None
    return value


def sanitize(payload: object, app: str, now: float) -> dict[str, object] | None:
    if not isinstance(payload, dict) or app not in {"Claude", "Codex", "MLX"}:
        return None
    session = identifier(payload.get("session_id"))
    event = payload.get("hook_event_name")
    if session is None or not isinstance(event, str) or event not in EVENTS:
        return None
    # Do not access transcript_path, cwd, prompt, tool_input, tool_response or any messages.
    return {"id": str(uuid.uuid4()), "app": app, "session": session, "timestamp": now,
            "event": event, "model": identifier(payload.get("model")),
            "tool": identifier(payload.get("tool_name")), "agent": identifier(payload.get("agent_id"))}


def append(event: dict[str, object], folder: Path) -> None:
    folder.mkdir(mode=0o700, parents=True, exist_ok=True)
    lock = os.open(folder / "session-events.lock", os.O_CREAT | os.O_RDWR | os.O_NOFOLLOW, 0o600)
    try:
        fcntl.flock(lock, fcntl.LOCK_EX)
        path = folder / "session-events.jsonl"
        descriptor = os.open(path, os.O_CREAT | os.O_RDWR | os.O_APPEND | os.O_NOFOLLOW, 0o600)
        with os.fdopen(descriptor, "a+b") as stream:
            if os.fstat(stream.fileno()).st_size > 1_048_576:
                stream.seek(-524288, os.SEEK_END)
                tail = stream.read().split(b"\n", 1)[-1]
                stream.seek(0); stream.truncate(); stream.write(tail)
            stream.write((json.dumps(event, separators=(",", ":")) + "\n").encode())
    finally:
        os.close(lock)


def main() -> None:
    try:
        if len(sys.argv) != 2:
            return
        raw = sys.stdin.buffer.read(1_048_577)
        if len(raw) > 1_048_576:
            return
        event = sanitize(json.loads(raw), sys.argv[1], time.time())
        if event is not None:
            append(event, Path.home() / "Library/Application Support/ArbiterSystem")
    except Exception:
        # Observation must never block an agent, add context, or reveal a payload in errors.
        return


if __name__ == "__main__":
    main()
