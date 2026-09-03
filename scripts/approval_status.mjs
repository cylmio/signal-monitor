export class ApprovalStatusTracker {
  constructor(graceMs = 600) {
    this.graceMs = graceMs;
    this.pending = new Map();
  }

  apply(events, observedAtMs = Date.now()) {
    for (const event of events) {
      if (!event.threadId) continue;
      if (event.kind === "candidate") {
        this.pending.set(event.threadId, observedAtMs);
      } else {
        this.pending.delete(event.threadId);
      }
    }
  }

  isWaiting(threadId, nowMs = Date.now()) {
    const observedAt = this.pending.get(threadId);
    return observedAt != null && nowMs - observedAt >= this.graceMs;
  }
}
