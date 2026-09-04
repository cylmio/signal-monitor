import assert from "node:assert/strict";
import test from "node:test";
import { execFileSync } from "node:child_process";
import { ApprovalStatusTracker, approvalCandidatePredicateSQL } from "./approval_status.mjs";

function isApprovalCandidate(body) {
  const literal = body.replaceAll("'", "''");
  return execFileSync("/usr/bin/sqlite3", [":memory:",
    `SELECT ${approvalCandidatePredicateSQL} FROM (SELECT '${literal}' AS feedback_log_body);`,
  ], { encoding: "utf8" }).trim() === "1";
}

test("removal approval candidates include absolute executables and both log formats", () => {
  for (const command of ["rm", "/bin/rm", "/usr/bin/rm"]) {
    for (const prefix of ['cmd:"', 'cmd: "', '"cmd":"', '"cmd": "']) {
      assert.equal(isApprovalCandidate(`ToolCall: tools.exec_command {${prefix}${command} -f /private/tmp/example.ps1"}`), true);
    }
  }
});

test("rm mentioned in an argument or a different executable is not a candidate", () => {
  for (const command of ["echo /bin/rm -f example", "ls /bin/rm", "/bin/rmdir example", "rmish example"]) {
    assert.equal(isApprovalCandidate(`ToolCall: tools.exec_command {cmd: "${command}"}`), false);
  }
});

test("common command wrappers retain removal approval detection", () => {
  for (const command of ["sudo /bin/rm", "command rm", "exec /usr/bin/rm"]) {
    assert.equal(isApprovalCandidate(`ToolCall: tools.exec_command {cmd: "${command} -f example"}`), true);
  }
});

test("absolute removal request waits and clears on approval without escalation metadata", () => {
  const tracker = new ApprovalStatusTracker(600);
  const body = 'ToolCall: tools.exec_command {cmd: "/bin/rm -f /private/tmp/example.ps1"}';
  tracker.apply([{ threadId: "alpha", kind: isApprovalCandidate(body) ? "candidate" : "toolCall" }], 1000);
  assert.equal(tracker.isWaiting("alpha", 1600), true);
  tracker.apply([{ threadId: "alpha", kind: "resolved" }], 2000);
  assert.equal(tracker.isWaiting("alpha", 2000), false);
  assert.equal(tracker.isRunningAfterApproval("alpha"), true);
});

test("approval candidate becomes waiting after a short grace period", () => {
  const tracker = new ApprovalStatusTracker(600);
  tracker.apply([{ threadId: "alpha", kind: "candidate" }], 1000);
  assert.equal(tracker.isWaiting("alpha", 1500), false);
  assert.equal(tracker.isWaiting("alpha", 1600), true);
});

test("approval resolution clears waiting state", () => {
  const tracker = new ApprovalStatusTracker(600);
  tracker.apply([{ threadId: "alpha", kind: "candidate" }], 1000);
  tracker.apply([{ threadId: "alpha", kind: "resolved" }], 2000);
  assert.equal(tracker.isWaiting("alpha", 3000), false);
  assert.equal(tracker.isRunningAfterApproval("alpha"), true);
});

test("approved command stays active until its tool call completes", () => {
  const tracker = new ApprovalStatusTracker(600);
  tracker.apply([{ threadId: "alpha", kind: "candidate" }], 1000);
  tracker.apply([{ threadId: "alpha", kind: "resolved" }], 2000);
  assert.equal(tracker.isRunningAfterApproval("alpha"), true);
  tracker.apply([{ threadId: "alpha", kind: "completed" }], 7000);
  assert.equal(tracker.isRunningAfterApproval("alpha"), false);
});

test("fast ordinary tool completion prevents a yellow flash", () => {
  const tracker = new ApprovalStatusTracker(600);
  tracker.apply([
    { threadId: "alpha", kind: "candidate" },
    { threadId: "alpha", kind: "completed" },
  ], 1000);
  assert.equal(tracker.isWaiting("alpha", 2000), false);
  assert.equal(tracker.isRunningAfterApproval("alpha"), false);
});
