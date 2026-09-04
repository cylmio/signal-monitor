#!/usr/bin/env node
// Mirror the Codex desktop sidebar snapshot into a local read-only JSON file.

import { execFileSync } from "node:child_process";
import { promises as fs } from "node:fs";
import net from "node:net";
import os from "node:os";
import path from "node:path";
import { rolloutInfoFromFile } from "./rollout_status.mjs";
import { ApprovalStatusTracker, approvalCandidatePredicateSQL } from "./approval_status.mjs";

const MAX_FRAME_BYTES = 8 * 1024 * 1024;
const hostParentPID = process.ppid;
const dataDirectory = process.env.SIGNAL_MONITOR_DATA_DIR
  ?? path.join(os.homedir(), "Library/Application Support/Signal Monitor");
const destination = path.join(dataDirectory, "desktop-status.json");
let lastSnapshotJSON = null;
let lastSnapshotWrite = 0;
const approvalLogDatabase = path.join(os.homedir(), ".codex/logs_2.sqlite");
let approvalLogCursor = (() => {
  try {
    const latest = Number(execFileSync("/usr/bin/sqlite3", [
      approvalLogDatabase,
      "SELECT COALESCE(MAX(id), 0) FROM logs;",
    ], { encoding: "utf8" }).trim());
    // Replay a small recent window so launching while a prompt is already open
    // can still reconstruct its candidate/resolved pair.
    return Math.max(0, latest - 5000);
  } catch {
    return 0;
  }
})();
const approvalTracker = new ApprovalStatusTracker();

function refreshApprovalSignals() {
  // Drain the replay window before publishing a snapshot. Otherwise an old
  // candidate from an early batch can briefly appear yellow before its later
  // resolved/completed row is consumed.
  for (let batch = 0; batch < 10; batch += 1) {
    const query = `
    SELECT id,
           thread_id AS threadId,
           CASE
             WHEN target = 'codex_core::stream_events_utils'
              AND feedback_log_body LIKE '%ToolCall:%'
              AND ${approvalCandidatePredicateSQL} THEN 'candidate'
             WHEN target = 'codex_core::stream_events_utils'
              AND feedback_log_body LIKE '%ToolCall:%' THEN 'toolCall'
             WHEN target = 'codex_core::session::handlers'
              AND (feedback_log_body LIKE '%ExecApproval {%' OR feedback_log_body LIKE '%PatchApproval {%') THEN 'resolved'
             WHEN target = 'codex_core::tools::parallel' THEN 'completed'
           END AS kind
      FROM logs
     WHERE id > ${Math.max(0, Math.trunc(approvalLogCursor))}
       AND thread_id IS NOT NULL
       AND (
         (target = 'codex_core::stream_events_utils' AND feedback_log_body LIKE '%ToolCall:%')
         OR target = 'codex_core::tools::parallel'
         OR (target = 'codex_core::session::handlers'
             AND (feedback_log_body LIKE '%ExecApproval {%' OR feedback_log_body LIKE '%PatchApproval {%'))
       )
     ORDER BY id ASC
     LIMIT 1000;
    `;
    try {
      const output = execFileSync("/usr/bin/sqlite3", ["-json", approvalLogDatabase, query], { encoding: "utf8" }).trim();
      if (!output) return;
      const events = JSON.parse(output);
      for (const event of events) approvalLogCursor = Math.max(approvalLogCursor, Number(event.id) || 0);
      approvalTracker.apply(events);
      if (events.length < 1000) return;
    } catch {
      // This signal is supplemental; rollout lifecycle state remains available.
      return;
    }
  }
}

function desktopPipe() {
  const output = execFileSync("/bin/ps", ["-axo", "command="], { encoding: "utf8" });
  for (const line of output.split("\n")) {
    if (!line.includes("features.code_mode_host=true")) continue;
    const match = line.match(/CODEX_APP_TOOLS_PIPE_PATH[^/]*(\/tmp\/codex-browser-use\/[0-9A-Fa-f-]+\.sock)/);
    if (match) return match[1];
  }
  throw new Error("Codex desktop status pipe was not found");
}

function interactionThreadId() {
  const database = path.join(os.homedir(), ".codex/state_5.sqlite");
  const query = "SELECT id FROM threads WHERE archived = 0 ORDER BY recency_at_ms DESC, updated_at DESC LIMIT 1;";
  const id = execFileSync("/usr/bin/sqlite3", [database, query], { encoding: "utf8" }).trim();
  if (!id) throw new Error("No local Codex task is available");
  return id;
}

function localTopLevelThreads() {
  refreshApprovalSignals();
  const database = path.join(os.homedir(), ".codex/state_5.sqlite");
  const query = `
    SELECT
      id,
      COALESCE(NULLIF(name, ''), NULLIF(preview, ''), NULLIF(title, ''), NULLIF(first_user_message, '')) AS title,
      cwd,
      rollout_path AS rolloutPath,
      CASE WHEN created_at_ms > 0 THEN created_at_ms / 1000.0 ELSE created_at END AS createdAt,
      CASE WHEN recency_at_ms > 0 THEN recency_at_ms / 1000.0
           WHEN recency_at > 0 THEN recency_at
           WHEN updated_at_ms > 0 THEN updated_at_ms / 1000.0
           ELSE updated_at END AS recencyAt
    FROM threads
    WHERE archived = 0
      AND substr(ltrim(source), 1, 1) <> '{'
    ORDER BY recencyAt DESC
    LIMIT 250;
  `;
  const output = execFileSync("/usr/bin/sqlite3", ["-json", database, query], { encoding: "utf8" }).trim();
  if (!output) return [];
  return JSON.parse(output).map(item => {
    const rollout = rolloutInfoFromFile(item.rolloutPath, Date.now(), item.cwd || null);
    return {
      kind: "codex",
      id: item.id,
      title: item.title || `Task ${String(item.id).slice(-6)}`,
      cwd: item.cwd || null,
      createdAt: item.createdAt ?? null,
      recencyAt: item.recencyAt ?? null,
      status: approvalTracker.isWaiting(item.id)
        ? "needsInput"
        : approvalTracker.isRunningAfterApproval(item.id)
          ? "active"
          : rollout.status,
      signalMonitorCompletionAt: rollout.completionAt == null ? null : rollout.completionAt / 1000,
    };
  });
}

function mergeLocalTopLevelThreads(snapshot) {
  const local = localTopLevelThreads();
  const apiItems = [...(snapshot.pinnedThreads ?? []), ...(snapshot.threads ?? [])];
  const apiByID = new Map(apiItems.map(item => [item.id, item]));
  const pinnedIDs = new Set((snapshot.pinnedThreads ?? []).map(item => item.id));
  const enriched = local.map(item => {
    const apiItem = apiByID.get(item.id);
    if (!apiItem) return item;
    return {
      ...item,
      ...apiItem,
      // The rollout belongs to the real desktop task. A separately queried API
      // can lag or return notLoaded, so it must not overwrite this local state.
      status: item.status !== "notLoaded" ? item.status : apiItem.status,
      createdAt: apiItem.createdAt ?? item.createdAt,
      recencyAt: apiItem.recencyAt ?? apiItem.updatedAt ?? item.recencyAt,
    };
  });
  snapshot.pinnedThreads = enriched.filter(item => pinnedIDs.has(item.id));
  snapshot.threads = enriched
    .filter(item => !pinnedIDs.has(item.id))
    .sort((a, b) => (b.recencyAt ?? 0) - (a.recencyAt ?? 0));
  return snapshot;
}

function textPayload(result) {
  if (!result.success) {
    const detail = result.contentItems?.find(entry => entry.type === "inputText")?.text
      ?? result.error?.message
      ?? "no error detail";
    throw new Error(`Codex desktop rejected a read-only status call: ${String(detail).slice(0, 500)}`);
  }
  const item = result.contentItems.find(entry => entry.type === "inputText");
  if (!item) throw new Error("Codex desktop returned no text snapshot");
  return JSON.parse(item.text);
}

async function callTool(client, tool, callerThreadId, argumentsValue, sequence) {
  try {
    return await client.request("tools/call", {
      arguments: argumentsValue,
      callId: `signal-monitor-${tool.name}-${sequence}`,
      namespace: tool.namespace,
      threadId: callerThreadId,
      tool: tool.name,
      turnId: `signal-monitor-poll-${sequence}`,
    });
  } catch (error) {
    throw new Error(`${tool.name} failed: ${error.message}`);
  }
}

async function enrichAttentionState(client, catalog, snapshot, sequence) {
  const waitTool = catalog.tools.find(item => item.name === "wait_threads");
  if (!waitTool) return;
  const all = [...(snapshot.pinnedThreads ?? []), ...(snapshot.threads ?? [])];
  const active = all.filter(item => item.kind === "codex" && item.status === "active").slice(0, 8);
  if (!active.length) return;
  const fallbackCaller = interactionThreadId();
  const caller = all.find(item => item.kind === "codex" && item.status !== "active")?.id ?? fallbackCaller;
  const targets = active.filter(item => item.id !== caller).map(item => ({
    threadId: item.id,
    ...(item.hostId ? { hostId: item.hostId } : {}),
  }));
  if (!targets.length) return;
  const result = await callTool(client, waitTool, caller, { targets, timeoutMs: 0 }, sequence);
  const detail = textPayload(result);
  for (const poll of detail.polls ?? []) {
    const id = poll.thread?.id;
    const target = all.find(item => item.id === id);
    if (!target) continue;
    target.signalMonitorActiveFlags = poll.thread?.status?.activeFlags ?? [];
    target.signalMonitorTurnStatus = poll.latestTurn?.status ?? null;
  }
  if (detail.wake?.threadId) {
    const target = all.find(item => item.id === detail.wake.threadId);
    if (target) target.signalMonitorNeedsAttention = true;
  }
}

function encodeFrame(message) {
  const payload = Buffer.from(JSON.stringify(message), "utf8");
  const frame = Buffer.allocUnsafe(payload.length + 4);
  frame.writeUInt32LE(payload.length, 0);
  payload.copy(frame, 4);
  return frame;
}

class NativePipeClient {
  constructor(pipePath) {
    this.pipePath = pipePath;
    this.nextId = 1;
    this.pending = new Map();
    this.buffer = Buffer.alloc(0);
  }

  async connect() {
    this.socket = net.createConnection(this.pipePath);
    this.socket.on("data", chunk => this.onData(chunk));
    this.socket.on("error", error => this.fail(error));
    this.socket.on("close", () => this.fail(new Error("Codex desktop pipe closed")));
    await new Promise((resolve, reject) => {
      this.socket.once("connect", resolve);
      this.socket.once("error", reject);
    });
  }

  request(method, params) {
    const id = this.nextId++;
    return new Promise((resolve, reject) => {
      this.pending.set(id, { resolve, reject });
      this.socket.write(encodeFrame({ id, jsonrpc: "2.0", method, params }));
    });
  }

  onData(chunk) {
    this.buffer = Buffer.concat([this.buffer, chunk]);
    while (this.buffer.length >= 4) {
      const length = this.buffer.readUInt32LE(0);
      if (length > MAX_FRAME_BYTES) return this.fail(new Error("Oversized desktop response"));
      if (this.buffer.length < length + 4) return;
      const payload = this.buffer.subarray(4, length + 4);
      this.buffer = this.buffer.subarray(length + 4);
      const message = JSON.parse(payload.toString("utf8"));
      const pending = this.pending.get(Number(message.id));
      if (!pending) continue;
      this.pending.delete(Number(message.id));
      if (message.error) {
        const detail = message.error.data == null ? "" : `: ${JSON.stringify(message.error.data)}`;
        pending.reject(new Error(`${message.error.message}${detail}`));
      }
      else pending.resolve(message.result);
    }
  }

  fail(error) {
    for (const pending of this.pending.values()) pending.reject(error);
    this.pending.clear();
    this.socket?.destroy();
  }
}

function terminate(exitCode = 0) {
  process.exit(exitCode);
}

for (const signal of ["SIGINT", "SIGTERM"]) {
  process.on(signal, () => terminate());
}

// A forced app quit does not give AppKit a chance to terminate its helper.
// Watch the original parent so the bridge cannot linger after a forced app quit.
setInterval(() => {
  try {
    process.kill(hostParentPID, 0);
  } catch {
    terminate();
  }
}, 1000);

async function writeSnapshot(payload) {
  await fs.mkdir(path.dirname(destination), { recursive: true });
  const stablePayload = { ...payload };
  delete stablePayload.signalMonitorUpdatedAt;
  const serialized = JSON.stringify(stablePayload);
  const now = Date.now() / 1000;
  if (serialized === lastSnapshotJSON && now - lastSnapshotWrite < 10) return;
  stablePayload.signalMonitorUpdatedAt = now;
  const temporary = `${destination}.${process.pid}.tmp`;
  await fs.writeFile(temporary, JSON.stringify(stablePayload), { mode: 0o600 });
  await fs.rename(temporary, destination);
  lastSnapshotJSON = serialized;
  lastSnapshotWrite = now;
}

const delay = milliseconds => new Promise(resolve => setTimeout(resolve, milliseconds));

function startLocalSnapshotPublisher(snapshotProvider) {
  let stopped = false;
  const run = async () => {
    while (!stopped) {
      let interval = 2000;
      try {
        const source = snapshotProvider();
        const snapshot = mergeLocalTopLevelThreads({
          ...source,
          pinnedThreads: [...(source.pinnedThreads ?? [])],
          threads: [...(source.threads ?? [])],
        });
        const tasks = [...(snapshot.pinnedThreads ?? []), ...(snapshot.threads ?? [])];
        if (tasks.some(item => item.status === "active" || item.status === "needsInput")) {
          interval = 750;
        }
        await writeSnapshot(snapshot);
      } catch {
        // A transient local read must not terminate the status bridge.
      }
      await delay(interval);
    }
  };
  void run();
  return () => {
    stopped = true;
  };
}

async function runDesktopPipe() {
  if (process.env.SIGNAL_MONITOR_DISABLE_DESKTOP_PIPE === "1") {
    throw new Error("Codex desktop pipe disabled for fallback verification");
  }
  const client = new NativePipeClient(desktopPipe());
  await client.connect();
  let catalog;
  try {
    catalog = await client.request("tools/list", { threadStartKind: "all" });
  } catch (error) {
    throw new Error(`tools/list failed: ${error.message}`);
  }
  const listTool = catalog.tools.find(item => item.name === "list_threads");
  if (!listTool) throw new Error("Codex desktop did not expose list_threads");
  const threadId = interactionThreadId();
  let latestSnapshot = { pinnedThreads: [], threads: [] };
  const stopPublisher = startLocalSnapshotPublisher(() => latestSnapshot);
  let sequence = 1;
  try {
    while (true) {
      const result = await callTool(client, listTool, threadId, { limit: 50 }, sequence);
      const snapshot = textPayload(result);
      await enrichAttentionState(client, catalog, snapshot, sequence);
      latestSnapshot = snapshot;
      sequence += 1;
      await delay(5000);
    }
  } finally {
    stopPublisher();
  }
}

async function runLocalFallback() {
  process.stderr.write("signal-monitor bridge: using local Codex database fallback\n");
  const stopPublisher = startLocalSnapshotPublisher(() => ({ pinnedThreads: [], threads: [] }));
  try {
    while (true) await delay(60_000);
  } finally {
    stopPublisher();
  }
}

try {
  await runDesktopPipe();
} catch (error) {
  process.stderr.write(`signal-monitor bridge: ${error.message}\n`);
  await runLocalFallback();
}
