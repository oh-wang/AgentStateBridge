import { EventEmitter } from "node:events";
import { watch } from "node:fs";
import { readFile } from "node:fs/promises";
import { homedir } from "node:os";
import { dirname, join } from "node:path";
import { createConnection } from "node:net";

export const defaultStatePath = join(
  homedir(),
  "Library",
  "Application Support",
  "AgentStateBridge",
  "state.json",
);

export const defaultSocketPath = join(
  dirname(defaultStatePath),
  "bridge.sock",
);

const knownStates = new Set([
  "inactive",
  "idle",
  "composing",
  "reasoning",
  "working",
  "completed",
  "unknown",
]);

/**
 * Node-side controller for Electron, Tauri sidecars, or a local web server.
 *
 * Events:
 * - "state": a new validated state object
 * - "waiting": state.json does not exist yet
 * - "error": an unexpected read, parse, or protocol error
 */
export class AgentStateController extends EventEmitter {
  constructor({
    statePath = defaultStatePath,
    socketPath,
    fallbackIntervalMs = 250,
    debounceMs = 30,
    socketReconnectIntervalMs = 500,
  } = {}) {
    super();
    this.statePath = statePath;
    this.socketPath = socketPath ?? join(dirname(statePath), "bridge.sock");
    this.fallbackIntervalMs = fallbackIntervalMs;
    this.debounceMs = debounceMs;
    this.socketReconnectIntervalMs = socketReconnectIntervalMs;
    this.current = null;
    this.fileWatcher = null;
    this.pollTimer = null;
    this.debounceTimer = null;
    this.socket = null;
    this.socketBuffer = "";
    this.socketReconnectTimer = null;
    this.started = false;
    this.waitingWasEmitted = false;
  }

  async start() {
    if (this.started) return;
    this.started = true;

    await this.readCurrent();
    this.startDirectoryWatcher();
    this.pollTimer = setInterval(() => {
      void this.readCurrent();
    }, this.fallbackIntervalMs);
    this.pollTimer.unref?.();
    this.connectSocket();
  }

  stop() {
    this.started = false;
    this.fileWatcher?.close();
    this.fileWatcher = null;
    clearInterval(this.pollTimer);
    clearTimeout(this.debounceTimer);
    clearTimeout(this.socketReconnectTimer);
    this.socket?.destroy();
    this.socket = null;
    this.socketBuffer = "";
    this.pollTimer = null;
    this.debounceTimer = null;
    this.socketReconnectTimer = null;
  }

  async readCurrent() {
    try {
      const text = await readFile(this.statePath, "utf8");
      this.acceptState(JSON.parse(text));
    } catch (error) {
      if (error?.code === "ENOENT") {
        if (!this.waitingWasEmitted) {
          this.waitingWasEmitted = true;
          this.emit("waiting", this.statePath);
        }
        return;
      }
      this.emit("error", error);
    }
  }

  acceptState(value) {
    const state = validateState(value);
    this.waitingWasEmitted = false;

    if (this.current && state.sequence <= this.current.sequence) return;
    this.current = state;
    this.emit("state", state);
  }

  connectSocket() {
    if (!this.started || this.socket) return;

    const socket = createConnection(this.socketPath);
    this.socket = socket;
    socket.setEncoding("utf8");

    socket.on("data", (chunk) => {
      this.socketBuffer += chunk;
      if (this.socketBuffer.length > 1_000_000) {
        this.emit("error", new Error("Agent state socket frame is too large."));
        socket.destroy();
        return;
      }

      let newlineIndex;
      while ((newlineIndex = this.socketBuffer.indexOf("\n")) >= 0) {
        const line = this.socketBuffer.slice(0, newlineIndex).trim();
        this.socketBuffer = this.socketBuffer.slice(newlineIndex + 1);
        if (!line) continue;
        try {
          this.acceptState(JSON.parse(line));
        } catch (error) {
          this.emit("error", error);
        }
      }
    });

    socket.on("error", (error) => {
      // The bridge may not be running yet. File watching and polling continue.
      if (error?.code !== "ENOENT" && error?.code !== "ECONNREFUSED") {
        this.emit("error", error);
      }
    });

    socket.on("close", () => {
      if (this.socket === socket) {
        this.socket = null;
        this.socketBuffer = "";
      }
      if (!this.started) return;
      clearTimeout(this.socketReconnectTimer);
      this.socketReconnectTimer = setTimeout(() => {
        this.socketReconnectTimer = null;
        this.connectSocket();
      }, this.socketReconnectIntervalMs);
      this.socketReconnectTimer.unref?.();
    });
  }

  startDirectoryWatcher() {
    try {
      this.fileWatcher = watch(dirname(this.statePath), (_event, filename) => {
        if (filename && filename !== "state.json") return;
        clearTimeout(this.debounceTimer);
        this.debounceTimer = setTimeout(() => {
          void this.readCurrent();
        }, this.debounceMs);
      });
      this.fileWatcher.on("error", (error) => {
        // Polling remains active, so a watcher failure is recoverable.
        this.emit("error", error);
      });
    } catch (error) {
      // The directory may not exist until AgentStateBridge starts.
      // The 250 ms fallback polling still discovers the first snapshot.
      if (error?.code !== "ENOENT") {
        this.emit("error", error);
      }
    }
  }
}

export function validateState(value) {
  if (!value || typeof value !== "object") {
    throw new TypeError("Agent state must be a JSON object.");
  }
  if (value.schemaVersion !== 1) {
    throw new TypeError(`Unsupported schemaVersion: ${value.schemaVersion}`);
  }
  if (!Number.isSafeInteger(value.sequence) || value.sequence < 0) {
    throw new TypeError("Agent state sequence must be a non-negative integer.");
  }
  if (!knownStates.has(value.state)) {
    throw new TypeError(`Unknown agent state: ${value.state}`);
  }
  return value;
}
