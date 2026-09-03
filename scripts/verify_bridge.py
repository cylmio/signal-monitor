#!/usr/bin/env python3
"""Read-only App Server integration check for Signal Monitor."""

import json
import os
import shutil
import select
import subprocess
import sys
import time

CODEX = os.environ.get("CODEX_EXECUTABLE") or shutil.which("codex")
if not CODEX and os.path.isfile("/Applications/ChatGPT.app/Contents/Resources/codex"):
    CODEX = "/Applications/ChatGPT.app/Contents/Resources/codex"


def send(process, payload):
    process.stdin.write(json.dumps(payload, separators=(",", ":")) + "\n")
    process.stdin.flush()


def wait_for_id(process, request_id, timeout=8):
    deadline = time.monotonic() + timeout
    while time.monotonic() < deadline:
        ready, _, _ = select.select([process.stdout], [], [], 0.5)
        if not ready:
            continue
        line = process.stdout.readline()
        if not line:
            break
        message = json.loads(line)
        if message.get("id") == request_id:
            return message
    raise TimeoutError(f"No response for request {request_id}")


def main():
    if not CODEX:
        raise RuntimeError("Codex executable not found; set CODEX_EXECUTABLE")
    process = subprocess.Popen(
        [CODEX, "app-server"],
        stdin=subprocess.PIPE,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        bufsize=1,
    )
    try:
        send(process, {
            "id": 1,
            "method": "initialize",
            "params": {"clientInfo": {
                "name": "signal-monitor-verifier",
                "title": "Signal Monitor Verifier",
                "version": "0.1.0",
            }},
        })
        initialized = wait_for_id(process, 1)
        if "result" not in initialized:
            raise RuntimeError(f"Initialize failed: {initialized}")
        send(process, {"method": "initialized"})
        send(process, {
            "id": 2,
            "method": "thread/list",
            "params": {
                "limit": 20,
                "sortKey": "updated_at",
                "sortDirection": "desc",
                "sourceKinds": [
                    "cli", "vscode", "exec", "appServer", "subAgent",
                    "subAgentReview", "subAgentCompact", "subAgentThreadSpawn",
                    "subAgentOther", "unknown",
                ],
            },
        })
        listed = wait_for_id(process, 2)
        threads = listed.get("result", {}).get("data", [])
        if not isinstance(threads, list):
            raise RuntimeError(f"Invalid thread/list result: {listed}")
        malformed = [item for item in threads if "id" not in item or "status" not in item]
        if malformed:
            raise RuntimeError(f"Threads without id/status: {len(malformed)}")
        states = {}
        for item in threads:
            kind = item.get("status", {}).get("type", "missing")
            states[kind] = states.get(kind, 0) + 1
        print(json.dumps({
            "bridge": "ok",
            "threadCount": len(threads),
            "uniqueThreadIds": len({item["id"] for item in threads}),
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
