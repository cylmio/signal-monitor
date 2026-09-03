export class ApprovalStatusTracker {
  constructor(graceMs = 600) {
    this.graceMs = graceMs;
    this.pending = new Map();
    this.runningAfterApproval = new Set();
  }

  apply(events, observedAtMs = Date.now()) {
    for (const event of events) {
      if (!event.threadId) continue;
      if (event.kind === "candidate") {
        this.pending.set(event.threadId, observedAtMs);
        this.runningAfterApproval.delete(event.threadId);
      } else if (event.kind === "resolved") {
        this.pending.delete(event.threadId);
        this.runningAfterApproval.add(event.threadId);
      } else {
        this.pending.delete(event.threadId);
        this.runningAfterApproval.delete(event.threadId);
      }
    }
  }

  isWaiting(threadId, nowMs = Date.now()) {
    const observedAt = this.pending.get(threadId);
    return observedAt != null && nowMs - observedAt >= this.graceMs;
  }

  isRunningAfterApproval(threadId) {
    return this.runningAfterApproval.has(threadId);
  }
}
