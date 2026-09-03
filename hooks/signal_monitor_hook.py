#!/usr/bin/env python3
"""Persist the latest Codex lifecycle event for one session. Produces no hook output."""

import json
import os
import pathlib
import sys
import tempfile
import time
import uuid

ALLOWED_EVENT_NAMES = {
    "SessionStart", "UserPromptSubmit", "PostToolUse", "PermissionRequest",
    "Stop", "Interrupt", "SessionEnd", "PreCompact", "PostCompact",
    "SubagentStart", "SubagentStop",
}


def main():
    event = json.load(sys.stdin)
    session_id = event.get("session_id")
    if not isinstance(session_id, str) or not session_id:
        return
    try:
        uuid.UUID(session_id)
    except ValueError:
        return
    event_name = event.get("hook_event_name")
    if event_name not in ALLOWED_EVENT_NAMES:
        return
    record = {
        "session_id": session_id,
        "hook_event_name": event_name,
        "signal_monitor_received_at": time.time(),
    }
    configured = os.environ.get("SIGNAL_MONITOR_DATA_DIR")
    base = pathlib.Path(configured) if configured else pathlib.Path.home() / "Library" / "Application Support" / "Signal Monitor"
    directory = base / "events"
    directory.mkdir(parents=True, exist_ok=True)
    destination = directory / f"{session_id}.json"
    descriptor, temporary = tempfile.mkstemp(prefix=".event-", suffix=".json", dir=directory)
    try:
        with os.fdopen(descriptor, "w", encoding="utf-8") as handle:
            json.dump(record, handle, ensure_ascii=False, separators=(",", ":"))
            handle.flush()
            os.fsync(handle.fileno())
        os.replace(temporary, destination)
    finally:
        if os.path.exists(temporary):
            os.unlink(temporary)


if __name__ == "__main__":
    main()
