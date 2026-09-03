import { closeSync, fstatSync, openSync, readSync } from "node:fs";

const MAX_READ_BYTES = 4 * 1024 * 1024;
const cache = new Map();

function readRange(filePath, start, length) {
  const descriptor = openSync(filePath, "r");
  try {
    const buffer = Buffer.allocUnsafe(length);
    const count = readSync(descriptor, buffer, 0, length, start);
    return buffer.subarray(0, count).toString("utf8");
  } finally {
    closeSync(descriptor);
  }
}

function applyLine(record, line) {
  let item;
  try {
    item = JSON.parse(line);
  } catch {
    return;
  }
  const payload = item.payload ?? {};
  if (item.type === "event_msg") {
    const type = String(payload.type ?? "").toLowerCase();
    if (type === "task_started") {
      record.state = "active";
      record.completedAt = null;
    } else if (type === "task_complete") {
      record.state = "completed";
      record.completedAt = Date.parse(item.timestamp) || Date.now();
    } else if (type === "turn_aborted") {
      record.state = "idle";
      record.completedAt = null;
    } else if (type.includes("approval") || type.includes("request_user_input") || type.includes("needs_input")) {
      record.state = "needsInput";
      record.completedAt = null;
    }
  }
  if (item.type === "response_item") {
    const name = String(payload.name ?? "").toLowerCase();
    const toolInput = typeof payload.input === "string"
      ? payload.input
      : JSON.stringify(payload.arguments ?? "");
    const requestsEscalation = /["']?sandbox_permissions["']?\s*:\s*["']require_escalated["']/.test(toolInput);
    if (payload.type === "custom_tool_call" && (name === "request_user_input" || requestsEscalation)) {
      record.state = "needsInput";
      record.completedAt = null;
    } else if (payload.type === "custom_tool_call_output" && record.state === "needsInput") {
      record.state = "active";
    }
  }
}

function applyChunk(record, text, startsMidFile) {
  let lines = text.split("\n");
  if (startsMidFile) lines = lines.slice(1);
  for (const line of lines) {
    if (line.trim()) applyLine(record, line);
  }
}

export function rolloutInfoFromFile(filePath, nowMs = Date.now()) {
  if (!filePath) return { status: "notLoaded", completionAt: null };
  let descriptor;
  let stat;
  try {
    descriptor = openSync(filePath, "r");
    stat = fstatSync(descriptor);
  } catch {
    if (descriptor != null) closeSync(descriptor);
    return { status: "notLoaded", completionAt: null };
  }
  closeSync(descriptor);

  let record = cache.get(filePath);
  if (!record || stat.size < record.size) {
    record = { size: 0, state: stat.mtimeMs > nowMs - 10_000 ? "active" : "idle", completedAt: null };
    const start = Math.max(0, stat.size - MAX_READ_BYTES);
    applyChunk(record, readRange(filePath, start, stat.size - start), start > 0);
  } else if (stat.size > record.size) {
    const start = Math.max(record.size, stat.size - MAX_READ_BYTES);
    applyChunk(record, readRange(filePath, start, stat.size - start), start > record.size);
  }
  record.size = stat.size;
  cache.set(filePath, record);

  return { status: record.state, completionAt: record.completedAt };
}

export function statusFromRollout(filePath, nowMs = Date.now()) {
  return rolloutInfoFromFile(filePath, nowMs).status;
}

export function clearRolloutStatusCache() {
  cache.clear();
}
