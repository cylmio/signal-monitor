import assert from "node:assert/strict";
import test from "node:test";
import { ApprovalStatusTracker } from "./approval_status.mjs";

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
