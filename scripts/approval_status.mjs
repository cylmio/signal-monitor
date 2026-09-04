// Keep classification inside SQLite: command bodies must not leave the query.
// Match the executable at the start of cmd, not an rm path mentioned in an argument.
const removalExecutables = ["rm", "/bin/rm", "/usr/bin/rm"];
const removalCommands = removalExecutables.flatMap(command =>
  [command, `sudo ${command}`, `command ${command}`, `exec ${command}`]);
const commandPrefixes = ['cmd:"', 'cmd: "', '"cmd":"', '"cmd": "'];
export const approvalCandidatePredicateSQL = `(
  feedback_log_body LIKE '%tools.apply_patch%'
  OR feedback_log_body LIKE '%request_user_input%'
  OR (feedback_log_body LIKE '%sandbox_permissions%' AND feedback_log_body LIKE '%require_escalated%')
  OR ${commandPrefixes.flatMap(prefix => removalCommands.map(command =>
    `feedback_log_body LIKE '%${prefix}${command} %'`
  )).join("\n  OR ")}
)`;

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
