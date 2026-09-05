import { test, expect, spyOn } from "bun:test";
import { mkdtempSync, rmSync, existsSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { pathToFileURL } from "node:url";
const root = process.env.PI_NATIVE_TEST_ROOT;
if (!root)
  throw new Error("Set PI_NATIVE_TEST_ROOT to the patched npm package");
const load = (path) => import(pathToFileURL(join(root, path)).href);
const { createExtensionRuntime, loadExtensionFromFactory } = await load(
  "dist/core/extensions/loader.js",
);
const { ExtensionRunner } = await load("dist/core/extensions/runner.js");
const { createEventBus } = await load("dist/core/event-bus.js");
const { SessionManager } = await load("dist/core/session-manager.js");
const { AgentSession } = await load("dist/core/agent-session.js");
const { OPENAI_CHECKPOINT_TYPE } = await load(
  "dist/core/openai-capabilities.js",
);
const registration = {
  provider: "openai-codex",
  model: "gpt-6-astra-fast",
  asyncTools: true,
  steering: true,
  asyncToolNames: ["read"],
};
const model = {
  api: "openai-codex-responses",
  provider: registration.provider,
  id: registration.model,
};
const assistant = (id = "c|item") => ({
  role: "assistant",
  api: model.api,
  provider: model.provider,
  model: model.id,
  content: [{ type: "toolCall", id, name: "read", arguments: { path: "a" } }],
  timestamp: 1,
  stopReason: "pending",
  openAI: { version: 1, exchangeId: "e", responseId: "r" },
  usage: {
    input: 0,
    output: 0,
    cacheRead: 0,
    cacheWrite: 0,
    totalTokens: 0,
    cost: { input: 0, output: 0, cacheRead: 0, cacheWrite: 0, total: 0 },
  },
});
const cp = (sm, phase, data = {}) =>
  sm.appendCustomEntry(OPENAI_CHECKPOINT_TYPE, {
    version: 1,
    exchangeId: "e",
    responseId: "r",
    phase,
    ...data,
  });

test("real loader/runner exact registry validates, snapshots, rejects duplicates and isolates reload", async () => {
  const runtime = createExtensionRuntime();
  let api;
  const value = structuredClone(registration);
  const extension = await loadExtensionFromFactory(
    (pi) => {
      api = pi;
      pi.registerOpenAICapabilities(value);
    },
    root,
    createEventBus(),
    runtime,
  );
  const runner = new ExtensionRunner(
    [extension],
    runtime,
    root,
    SessionManager.inMemory(root),
    {},
  );
  value.asyncToolNames.push("write");
  const found = runner.getOpenAICapabilities(model);
  expect(found.asyncToolNames).toEqual(["read"]);
  expect(Object.isFrozen(found)).toBe(true);
  expect(Object.isFrozen(found.asyncToolNames)).toBe(true);
  expect(
    runner.getOpenAICapabilities({ ...model, id: "other-fast" }),
  ).toBeUndefined();
  expect(
    runner.getOpenAICapabilities({ ...model, provider: "other" }),
  ).toBeUndefined();
  expect(
    runner.getOpenAICapabilities({ ...model, api: "openai-responses" }),
  ).toBeUndefined();
  expect(() => api.registerOpenAICapabilities(registration)).toThrow(
    "Duplicate",
  );
  runner.isIdleFn = () => false;
  expect(() =>
    api.registerOpenAICapabilities({ ...registration, model: "new" }),
  ).toThrow("idle");
  runner.isIdleFn = () => true;
  api.registerOpenAICapabilities({
    ...registration,
    model: "new",
    asyncToolNames: [],
  });
  runtime.invalidate();
  expect(runtime.openAICapabilities.size).toBe(0);
  expect(() =>
    api.registerOpenAICapabilities({ ...registration, model: "stale" }),
  ).toThrow("stale");
  expect(createExtensionRuntime().openAICapabilities.size).toBe(0);
});

test("invalid or failed extension registration never leaks into runtime", async () => {
  for (const patch of [
    { provider: "" },
    { model: " " },
    { steering: 1 },
    { asyncTools: "yes" },
    { asyncToolNames: ["read", "read"] },
    { asyncToolNames: [""] },
    { asyncTools: false, asyncToolNames: [] },
  ]) {
    const runtime = createExtensionRuntime();
    await expect(
      loadExtensionFromFactory(
        (pi) => pi.registerOpenAICapabilities({ ...registration, ...patch }),
        root,
        createEventBus(),
        runtime,
      ),
    ).rejects.toThrow();
    expect(runtime.openAICapabilities.size).toBe(0);
  }
  const runtime = createExtensionRuntime();
  await expect(
    loadExtensionFromFactory(
      (pi) => {
        pi.registerOpenAICapabilities(registration);
        throw new Error("load failed");
      },
      root,
      createEventBus(),
      runtime,
    ),
  ).rejects.toThrow("load failed");
  expect(runtime.openAICapabilities.size).toBe(0);
});

test("checkpoint reaches disk before first assistant and recovery provides unknown outcome, branch isolation", () => {
  const dir = mkdtempSync(join(tmpdir(), "pi-native-session-"));
  try {
    const sm = SessionManager.create(dir, dir);
    const first = cp(sm, "call_intent", {
      callId: "c|item",
      assistant: assistant(),
    });
    expect(existsSync(sm.getSessionFile())).toBe(true);
    const reopened = SessionManager.open(sm.getSessionFile(), dir);
    const messages = reopened.buildSessionContext().messages;
    expect(messages.map((m) => m.role)).toEqual(["assistant", "toolResult"]);
    expect(messages[1].content[0].text).toContain("unknown");
    expect(messages[1].openAI.nonRetryable).toBe(true);
    sm.branch(first);
    sm.appendMessage({ role: "user", content: "other branch", timestamp: 4 });
    const branch = sm.getLeafId();
    cp(sm, "call_intent", {
      callId: "other|item",
      assistant: assistant("other|item"),
    });
    sm.branch(branch);
    expect(
      sm
        .buildSessionContext()
        .messages.some((m) => m.toolCallId === "other|item"),
    ).toBe(false);
  } finally {
    rmSync(dir, { recursive: true, force: true });
  }
});

test("terminal messages supersede snapshots without moving assistant after results", () => {
  const sm = SessionManager.inMemory(root);
  cp(sm, "call_intent", { callId: "c|item", assistant: assistant() });
  const result = {
    role: "toolResult",
    toolCallId: "c|item",
    toolName: "read",
    content: [{ type: "text", text: "saved" }],
    timestamp: 2,
    isError: false,
    openAI: { version: 1, exchangeId: "e", responseId: "r" },
  };
  cp(sm, "call_complete", { callId: "c|item", assistant: assistant(), result });
  sm.appendMessage({
    ...assistant(),
    content: [...assistant().content, { type: "text", text: "terminal" }],
    stopReason: "error",
  });
  sm.appendMessage({
    ...result,
    content: [{ type: "text", text: "terminal result" }],
  });
  const messages = sm.buildSessionContext().messages;
  expect(messages.length).toBe(2);
  expect(messages[0].content[1].text).toBe("terminal");
  expect(messages[1].content[0].text).toBe("terminal result");
});

test("late sibling completion does not overwrite newer assistant intent", () => {
  const sm = SessionManager.inMemory(root);
  cp(sm, "call_intent", { callId: "c|item", assistant: assistant() });
  const next = {
    ...assistant(),
    content: [...assistant().content, ...assistant("second|item").content],
  };
  cp(sm, "call_intent", { callId: "second|item", assistant: next });
  cp(sm, "call_complete", {
    callId: "c|item",
    assistant: assistant(),
    result: {
      role: "toolResult",
      toolCallId: "c|item",
      toolName: "read",
      content: [],
      timestamp: 2,
      isError: false,
    },
  });
  expect(
    sm
      .buildSessionContext()
      .messages[0].content.filter((c) => c.type === "toolCall")
      .map((c) => c.id),
  ).toEqual(["c|item", "second|item"]);
});

test("accepted input is uncertain after crash and incorporated input is not duplicated", () => {
  const sm = SessionManager.inMemory(root);
  const message = {
    role: "user",
    content: [{ type: "text", text: "do not auto replay" }],
    timestamp: 2,
    openAI: { version: 1, exchangeId: "e", deliveryId: "d" },
  };
  cp(sm, "steer_sent", { messages: [message] });
  cp(sm, "steer_accepted", { messages: [message] });
  let messages = sm.buildSessionContext().messages;
  expect(messages.map((m) => m.role)).toEqual(["custom"]);
  expect(messages[0].details.messages[0]).toEqual(message);
  cp(sm, "steer_incorporated", { messages: [message] });
  sm.appendMessage(message);
  messages = sm.buildSessionContext().messages;
  expect(messages.map((m) => m.role)).toEqual(["user"]);
});

function sessionFixture() {
  let handler;
  const steered = [],
    followed = [];
  const sm = SessionManager.inMemory(root);
  const runner = {
    getOpenAICapabilities: () => registration,
    emit: async () => {},
    hasHandlers: () => false,
    getUIContext: () => ({ notify() {} }),
  };
  class TestSession extends AgentSession {
    _buildRuntime() {
      this._extensionRunner = runner;
    }
  }
  const agent = {
    state: { model, messages: [], tools: [] },
    subscribe: (fn) => {
      handler = fn;
      return () => {};
    },
    steer: (m) => steered.push(m),
    followUp: (m) => followed.push(m),
    clearAllQueues() {},
    hasQueuedMessages: () => true,
  };
  const session = new TestSession({
    agent,
    sessionManager: sm,
    settingsManager: {
      getRetrySettings: () => ({ enabled: true, maxRetries: 3 }),
    },
    cwd: root,
    resourceLoader: {},
    modelRuntime: {},
  });
  session._resolveOpenAICapabilities();
  return { session, agent, sm, handler, steered, followed, runner };
}

test("native identical text/image queue deliveries remove only their stable identity", async () => {
  const { session, handler, steered, followed } = sessionFixture();
  const image = {
    type: "image",
    source: { type: "base64", mediaType: "image/png", data: "synthetic" },
  };
  await session._queueSteer("same", [image]);
  await session._queueSteer("same", [image]);
  await session._queueFollowUp("same", [image]);
  expect(
    new Set([...steered, ...followed].map((m) => m.openAI.deliveryId)).size,
  ).toBe(3);
  await handler({
    type: "message_start",
    message: { role: "user", content: "same", timestamp: 1 },
  });
  expect(session.getSteeringMessages()).toEqual(["same", "same"]);
  expect(session.getFollowUpMessages()).toEqual(["same"]);
  await handler({ type: "message_start", message: followed[0] });
  expect(session.getSteeringMessages()).toEqual(["same", "same"]);
  expect(session.getFollowUpMessages()).toEqual([]);
  await handler({ type: "message_start", message: steered[1] });
  expect(session.getSteeringMessages()).toEqual(["same"]);
  const pending = session.clearQueue();
  expect(pending.messages).toEqual([steered[0]]);
  expect(pending.messages[0].content[1]).toEqual(image);
});

test("recovered uncertainty is persisted once for transcript rendering", () => {
  const { session, sm } = sessionFixture();
  const message = {
    role: "user",
    content: "pending",
    timestamp: 1,
    openAI: { version: 1, exchangeId: "e", deliveryId: "d" },
  };
  cp(sm, "steer_accepted", { messages: [message] });
  session._persistOpenAIRecoveryWarnings();
  session._persistOpenAIRecoveryWarnings();
  expect(
    sm.getBranch().filter((entry) => entry.type === "custom_message"),
  ).toHaveLength(1);
  expect(
    sm
      .buildSessionContext()
      .messages.filter((message) => message.role === "custom"),
  ).toHaveLength(1);
});

test("prepared native factory preserves resolved authentication, endpoint, environment and hooks", async () => {
  const ai = await load("node_modules/@earendil-works/pi-ai/dist/index.js");
  const { ModelRuntime } = await load("dist/core/model-runtime.js");
  const exchange = { close() {} };
  let captured;
  const factory = spyOn(ai, "createOpenAICodexExchange").mockImplementation(
    async (...args) => {
      captured = args;
      return exchange;
    },
  );
  try {
    const runtime = Object.create(ModelRuntime.prototype);
    runtime.models = { getProvider: () => ({ id: model.provider }) };
    runtime.getAuth = async (_model, overrides) => {
      expect(overrides.env).toEqual({ CALLER: "present" });
      return {
        auth: {
          apiKey: "synthetic-key",
          baseUrl: "https://synthetic.invalid/v1",
          headers: { Authorization: "synthetic", "X-Remove": "old" },
        },
        env: { PROVIDER: "present" },
      };
    };
    const { session, runner } = sessionFixture();
    session._modelRuntime = runtime;
    session.settingsManager = {
      getHttpIdleTimeoutMs: () => 5000,
      getWebSocketConnectTimeoutMs: () => 9000,
      getProviderHeaders: () => undefined,
      getEnableInstallTelemetry: () => false,
    };
    runner.hasHandlers = (event) => event === "before_provider_headers";
    runner.emitBeforeProviderHeaders = (headers) => {
      expect(headers.Authorization).toBe("synthetic");
      return { ...headers, "X-Remove": null, "X-Hook": "yes" };
    };
    const onPayload = (payload) => ({ ...payload, model: "alias-hook" });
    expect(
      await session._createOpenAIExchange(
        model,
        { messages: [] },
        {
          env: { CALLER: "present" },
          headers: { "X-Caller": "yes" },
          onPayload,
        },
      ),
    ).toBe(exchange);
    expect(captured[0].baseUrl).toBe("https://synthetic.invalid/v1");
    expect(captured[2].apiKey).toBe("synthetic-key");
    expect(captured[2].env).toEqual({ PROVIDER: "present", CALLER: "present" });
    expect(captured[2].headers).toMatchObject({
      Authorization: "synthetic",
      "X-Caller": "yes",
      "X-Remove": null,
      "X-Hook": "yes",
    });
    expect(captured[2].onPayload({}).model).toBe("alias-hook");
    expect(captured[2].maxRetries).toBe(0);
    expect(captured[2].transformHeaders).toBeUndefined();
  } finally {
    factory.mockRestore();
  }
});

test("checkpoint snapshot is available to permission hooks and native errors never retry or compact", async () => {
  const { session, handler, sm } = sessionFixture();
  const record = {
    version: 1,
    exchangeId: "e",
    responseId: "r",
    phase: "call_intent",
    callId: "c|item",
    assistant: assistant(),
  };
  await handler({ type: "openai_checkpoint", record });
  record.assistant.content[0].arguments.path = "mutated";
  expect(sm.buildSessionContext().messages[0].content[0].arguments.path).toBe(
    "a",
  );
  const error = {
    ...assistant(),
    stopReason: "error",
    errorMessage: "503 overloaded",
  };
  expect(session._isRetryableError(error)).toBe(false);
  expect(await session._checkCompaction(error)).toBe(false);
  session._lastAssistantMessage = error;
  expect(await session._handlePostAgentRun()).toBe(false);
  session._isAgentRunActive = true;
  await expect(session.setModel(model)).rejects.toThrow("Wait");
  await expect(session.compact()).rejects.toThrow("Wait");
  await expect(session.reload()).rejects.toThrow("Wait");
});
