#!/usr/bin/env python3
"""Read-only local bridge integration check for Signal Monitor."""

import json
import os
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile
import time


ROOT = Path(__file__).resolve().parent.parent
BRIDGE = ROOT / "scripts" / "desktop_status_bridge.mjs"
NODE = os.environ.get("NODE_EXECUTABLE") or shutil.which("node")


def main():
    if not NODE:
        raise RuntimeError("Node executable not found; set NODE_EXECUTABLE")
    if not BRIDGE.is_file():
        raise RuntimeError(f"Bridge script not found: {BRIDGE}")

    with tempfile.TemporaryDirectory(prefix="signal-monitor-verify-") as data_dir:
        environment = os.environ.copy()
        environment["SIGNAL_MONITOR_DATA_DIR"] = data_dir
        environment["SIGNAL_MONITOR_DISABLE_DESKTOP_PIPE"] = "1"
        process = subprocess.Popen(
            [NODE, str(BRIDGE)],
            stdout=subprocess.DEVNULL,
            stderr=subprocess.PIPE,
            text=True,
            env=environment,
        )
        try:
            destination = Path(data_dir) / "desktop-status.json"
            deadline = time.monotonic() + 8
            while time.monotonic() < deadline and not destination.is_file():
                if process.poll() is not None:
                    detail = process.stderr.read().strip()
                    raise RuntimeError(f"Bridge exited early: {detail}")
                time.sleep(0.1)
            if not destination.is_file():
                raise TimeoutError("Bridge did not publish a snapshot within 8 seconds")

            snapshot = json.loads(destination.read_text(encoding="utf-8"))
            threads = snapshot.get("threads", [])
            pinned = snapshot.get("pinnedThreads", [])
            if not isinstance(threads, list) or not isinstance(pinned, list):
                raise RuntimeError("Snapshot task collections are invalid")
            tasks = pinned + threads
            malformed = [item for item in tasks if "id" not in item or "status" not in item]
            if malformed:
                raise RuntimeError(f"Tasks without id/status: {len(malformed)}")

            states = {}
            for item in tasks:
                state = item.get("status", "missing")
                states[state] = states.get(state, 0) + 1
            print(json.dumps({
                "bridge": "ok",
                "source": "local-codex-database",
                "taskCount": len(tasks),
                "uniqueTaskIds": len({item["id"] for item in tasks}),
                "statusCounts": states,
            }, ensure_ascii=False, indent=2))
        finally:
            process.terminate()
            try:
                process.wait(timeout=2)
            except subprocess.TimeoutExpired:
                process.kill()


if __name__ == "__main__":
    try:
        main()
    except Exception as exc:
        print(f"bridge verification failed: {exc}", file=sys.stderr)
        sys.exit(1)
