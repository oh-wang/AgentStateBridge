import assert from "node:assert/strict";
import { mkdtemp, rm, writeFile } from "node:fs/promises";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { createServer } from "node:net";
import test from "node:test";
import {
  AgentStateController,
  validateState,
} from "./agent-state-controller.mjs";

function snapshot(sequence, state = "working") {
  return {
    schemaVersion: 1,
    sequence,
    timestamp: "2026-07-27T12:00:00Z",
    application: {
      id: "chatgpt",
      bundleId: "com.openai.codex",
      version: "test",
    },
    state,
    previousState: "composing",
    confidence: 0.96,
    evidence: ["stop-button-present"],
  };
}

test("validates the supported protocol", () => {
  assert.equal(validateState(snapshot(1)).state, "working");
  assert.throws(
    () => validateState({ ...snapshot(1), schemaVersion: 2 }),
    /Unsupported schemaVersion/,
  );
  assert.throws(
    () => validateState({ ...snapshot(1), state: "private-text" }),
    /Unknown agent state/,
  );
});

test("emits each sequence only once", async () => {
  const directory = await mkdtemp(join(tmpdir(), "agent-state-js-"));
  const statePath = join(directory, "state.json");

  try {
    await writeFile(statePath, JSON.stringify(snapshot(7)));
    const controller = new AgentStateController({
      statePath,
      fallbackIntervalMs: 10_000,
    });
    const received = [];
    controller.on("state", (state) => received.push(state.sequence));

    await controller.readCurrent();
    await controller.readCurrent();
    await writeFile(statePath, JSON.stringify(snapshot(8, "completed")));
    await controller.readCurrent();
    controller.stop();

    assert.deepEqual(received, [7, 8]);
    assert.equal(controller.current.state, "completed");
  } finally {
    await rm(directory, { recursive: true, force: true });
  }
});

test("receives rapid states from the Unix socket", async () => {
  const directory = await mkdtemp(join(tmpdir(), "asb-js-"));
  const statePath = join(directory, "state.json");
  const socketPath = join(directory, "bridge.sock");
  const server = createServer((connection) => {
    connection.write(`${JSON.stringify(snapshot(8, "reasoning"))}\n`);
    connection.write(`${JSON.stringify(snapshot(9, "working"))}\n`);
  });
  let controller;

  try {
    await writeFile(statePath, JSON.stringify(snapshot(7, "composing")));
    await new Promise((resolve, reject) => {
      server.once("error", reject);
      server.listen(socketPath, resolve);
    });

    controller = new AgentStateController({
      statePath,
      socketPath,
      fallbackIntervalMs: 10_000,
      socketReconnectIntervalMs: 10_000,
    });
    const received = [];
    const allStates = new Promise((resolve, reject) => {
      const timeout = setTimeout(
        () => reject(new Error("Timed out waiting for socket states.")),
        2_000,
      );
      controller.on("state", (state) => {
        received.push(state.sequence);
        if (received.length === 3) {
          clearTimeout(timeout);
          resolve();
        }
      });
      controller.on("error", reject);
    });

    await controller.start();
    await allStates;
    controller.stop();
    assert.deepEqual(received, [7, 8, 9]);
    assert.equal(controller.current.state, "working");
  } finally {
    controller?.stop();
    await new Promise((resolve) => server.close(resolve));
    await rm(directory, { recursive: true, force: true });
  }
});
