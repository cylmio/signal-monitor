import assert from "node:assert/strict";
import { appendFileSync, mkdtempSync, writeFileSync } from "node:fs";
import os from "node:os";
import path from "node:path";
import test from "node:test";
import { clearRolloutStatusCache, rolloutInfoFromFile, statusFromRollout } from "./rollout_status.mjs";

const line = (timestamp, type, payload) => JSON.stringify({ timestamp, type, payload }) + "\n";

test("derives lifecycle state from appended rollout records", () => {
  clearRolloutStatusCache();
  const directory = mkdtempSync(path.join(os.tmpdir(), "signal-monitor-rollout-"));
  const file = path.join(directory, "rollout.jsonl");
  const now = Date.parse("2026-09-03T12:00:00.000Z");

  writeFileSync(file, line("2026-09-03T12:00:00.000Z", "event_msg", { type: "task_started" }));
  assert.equal(statusFromRollout(file, now), "active");

  appendFileSync(file, line("2026-09-03T12:00:00.500Z", "response_item", {
    type: "custom_tool_call", name: "request_user_input", status: "completed",
  }));
  assert.equal(statusFromRollout(file, now + 500), "needsInput");

  appendFileSync(file, line("2026-09-03T12:00:01.000Z", "response_item", { type: "custom_tool_call_output" }));
  assert.equal(statusFromRollout(file, now + 1000), "active");

  appendFileSync(file, line("2026-09-03T12:00:02.000Z", "event_msg", { type: "task_complete" }));
  assert.equal(statusFromRollout(file, now + 2000), "completed");
  assert.equal(statusFromRollout(file, now + 60_000), "completed");
  assert.equal(rolloutInfoFromFile(file, now + 60_000).completionAt, now + 2000);
});

test("an aborted turn is idle", () => {
  clearRolloutStatusCache();
  const directory = mkdtempSync(path.join(os.tmpdir(), "signal-monitor-rollout-"));
  const file = path.join(directory, "rollout.jsonl");
  writeFileSync(file,
    line("2026-09-03T12:00:00.000Z", "event_msg", { type: "task_started" }) +
    line("2026-09-03T12:00:01.000Z", "event_msg", { type: "turn_aborted" })
  );
  assert.equal(statusFromRollout(file, Date.parse("2026-09-03T12:00:01.100Z")), "idle");
});

test("an escalated tool call waits for user permission", () => {
  clearRolloutStatusCache();
  const directory = mkdtempSync(path.join(os.tmpdir(), "signal-monitor-rollout-"));
  const file = path.join(directory, "rollout.jsonl");
  const now = Date.parse("2026-09-03T12:00:00.000Z");
  writeFileSync(file,
    line("2026-09-03T12:00:00.000Z", "event_msg", { type: "task_started" }) +
    line("2026-09-03T12:00:01.000Z", "response_item", {
      type: "custom_tool_call",
      name: "exec",
      input: 'await tools.exec_command({ sandbox_permissions: "require_escalated" })',
    })
  );
  assert.equal(statusFromRollout(file, now + 1000), "needsInput");

  appendFileSync(file, line("2026-09-03T12:00:02.000Z", "response_item", {
    type: "custom_tool_call_output",
  }));
  assert.equal(statusFromRollout(file, now + 2000), "active");
});
