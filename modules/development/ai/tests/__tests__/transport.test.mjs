import assert from "node:assert/strict";
import { join } from "node:path";
import { pathToFileURL } from "node:url";
import test from "node:test";
import { withWebSocket } from "../websocket-fixture.mjs";

const root = process.env.PI_NATIVE_TEST_ROOT;
if (!root) throw new Error("Set PI_NATIVE_TEST_ROOT to the patched Pi package");
const moduleUrl = pathToFileURL(
  join(
    root,
    "node_modules/@earendil-works/pi-ai/dist/api/openai-codex-responses.js",
  ),
);
const { createOpenAICodexExchange } = await import(moduleUrl.href);

class FakeWebSocket {
  static instances = [];
  constructor(url, options) {
    this.url = url;
    this.options = options;
    this.readyState = 0;
    this.listeners = new Map();
    this.sent = [];
    FakeWebSocket.instances.push(this);
    queueMicrotask(() => {
      this.readyState = 1;
      this.emit("open", {});
    });
  }
  addEventListener(type, listener) {
    const listeners = this.listeners.get(type) ?? [];
    listeners.push(listener);
    this.listeners.set(type, listeners);
  }
  removeEventListener(type, listener) {
    this.listeners.set(
      type,
      (this.listeners.get(type) ?? []).filter((entry) => entry !== listener),
    );
  }
  send(frame) {
    this.sent.push(JSON.parse(frame));
  }
  close(code = 1000, reason = "") {
    this.readyState = 3;
    this.emit("close", { code, reason, wasClean: true });
  }
  emit(type, event) {
    for (const listener of this.listeners.get(type) ?? []) listener(event);
  }
  event(value) {
    this.emit("message", { data: JSON.stringify(value) });
  }
}

function token() {
  const payload = Buffer.from(
    JSON.stringify({
      "https://api.openai.com/auth": { chatgpt_account_id: "acct_test" },
    }),
  ).toString("base64");
  return `a.${payload}.c`;
}

function model() {
  return {
    id: "gpt-6-astra-fast",
    name: "Astra",
    api: "openai-codex-responses",
    provider: "openai-codex",
    baseUrl: "https://chatgpt.test/backend-api",
    reasoning: false,
    input: ["text"],
    cost: { input: 0, output: 0, cacheRead: 0, cacheWrite: 0 },
    contextWindow: 1,
    maxTokens: 1,
  };
}

function context() {
  return {
    systemPrompt: "test",
    messages: [
      {
        role: "user",
        content: [{ type: "text", text: "hello" }],
        timestamp: 1,
      },
    ],
    tools: [
      {
        name: "read",
        description: "read",
        parameters: { type: "object", properties: {}, required: [] },
      },
      {
        name: "grep",
        description: "grep",
        parameters: { type: "object", properties: {}, required: [] },
      },
    ],
  };
}

async function withFakeSocket(run) {
  FakeWebSocket.instances = [];
  await withWebSocket(FakeWebSocket, run);
}

test("builds a stable post-hook Codex request and advertises only marked client tools", async () => {
  await withFakeSocket(async () => {
    const exchange = await createOpenAICodexExchange(model(), context(), {
      apiKey: token(),
      openAICapabilities: {
        asyncTools: true,
        steering: true,
        asyncToolNames: ["read"],
      },
      onPayload: (body) => ({
        ...body,
        model: "gpt-6-astra",
        service_tier: "priority",
        tools: [...body.tools, { type: "web_search" }],
      }),
    });
    assert.deepEqual([...exchange.advertisedAsyncToolNames], ["read"]);
    exchange.create();
    const [request] = FakeWebSocket.instances[0].sent;
    assert.equal(request.type, "response.create");
    assert.equal(request.model, "gpt-6-astra");
    assert.equal(request.service_tier, "priority");
    assert.equal(
      request.tools.find((tool) => tool.name === "read").async,
      true,
    );
    assert.equal(
      request.tools.find((tool) => tool.name === "grep").async,
      undefined,
    );
    assert.equal(
      request.tools.find((tool) => tool.type === "web_search").async,
      undefined,
    );
    exchange.close();
  });
});

test("rejects SSE and contradictory async declarations before creating a socket", async () => {
  await assert.rejects(
    createOpenAICodexExchange(model(), context(), {
      apiKey: token(),
      transport: "sse",
      openAICapabilities: { asyncTools: true, steering: false },
    }),
    /WebSocket transport/,
  );
  await withFakeSocket(async () => {
    await assert.rejects(
      createOpenAICodexExchange(model(), context(), {
        apiKey: token(),
        openAICapabilities: { asyncTools: false, steering: false },
        onPayload: (body) => ({
          ...body,
          tools: [{ type: "function", name: "read", async: true }],
        }),
      }),
      /not enabled/,
    );
    assert.equal(FakeWebSocket.instances.length, 0);
  });
});

test("keeps one reader across terminal responses and sends steer plus successor continuation", async () => {
  await withFakeSocket(async () => {
    const exchange = await createOpenAICodexExchange(model(), context(), {
      apiKey: token(),
      openAICapabilities: {
        asyncTools: true,
        steering: true,
        asyncToolNames: [],
      },
    });
    const socket = FakeWebSocket.instances[0];
    exchange.create();
    socket.event({ type: "response.created", response: { id: "r1" } });
    socket.event({ type: "response.output_text.delta", delta: "first" });
    const iterator = exchange.events[Symbol.asyncIterator]();
    assert.equal((await iterator.next()).value.type, "response.created");
    assert.equal(
      (await iterator.next()).value.type,
      "response.output_text.delta",
    );
    await assert.rejects(
      exchange.create(
        [
          {
            type: "function_call_output",
            call_id: "call_early",
            output: "ready",
          },
        ],
        "r1",
      ),
      /response is active/,
    );
    exchange.steer("r1", "change direction");
    assert.deepEqual(socket.sent.at(-1), {
      type: "response.steer",
      previous_response_id: "r1",
      input: "change direction",
    });
    socket.event({
      type: "response.incomplete",
      response: { id: "r1", incomplete_details: { reason: "steered" } },
    });
    socket.event({ type: "response.created", response: { id: "r2" } });
    socket.event({ type: "response.completed", response: { id: "r2" } });
    assert.equal((await iterator.next()).value.type, "response.incomplete");
    assert.equal((await iterator.next()).value.response.id, "r2");
    assert.equal((await iterator.next()).value.type, "response.completed");
    await exchange.create(
      [{ type: "function_call_output", call_id: "call_1", output: "done" }],
      "r2",
    );
    assert.equal(socket.sent.at(-1).type, "response.create");
    assert.equal(socket.sent.at(-1).previous_response_id, "r2");
    exchange.close();
  });
});

test("aborts the single reader without replaying a request", async () => {
  await withFakeSocket(async () => {
    const controller = new AbortController();
    const exchange = await createOpenAICodexExchange(model(), context(), {
      apiKey: token(),
      signal: controller.signal,
      openAICapabilities: { asyncTools: false, steering: false },
    });
    const socket = FakeWebSocket.instances[0];
    exchange.create();
    const iterator = exchange.events[Symbol.asyncIterator]();
    controller.abort();
    await assert.rejects(iterator.next(), /Request was aborted/);
    assert.equal(socket.sent.length, 1);
  });
});

test("refreshes newly activated tools and reasoning on explicit continuations", async () => {
  await withFakeSocket(async () => {
    let hooks = 0;
    const exchange = await createOpenAICodexExchange(
      { ...model(), reasoning: true, compat: { supportsToolSearch: true } },
      context(),
      {
        apiKey: token(),
        reasoning: "high",
        openAICapabilities: { asyncTools: true, steering: true },
        onPayload(body) {
          hooks++;
          return { ...body, model: "gpt-6-astra", service_tier: "priority" };
        },
      },
    );
    await exchange.create();
    const socket = FakeWebSocket.instances[0];
    socket.event({ type: "response.created", response: { id: "r1" } });
    socket.event({ type: "response.completed", response: { id: "r1" } });
    const iterator = exchange.events[Symbol.asyncIterator]();
    await iterator.next();
    await iterator.next();
    const nextContext = context();
    nextContext.tools.push({
      name: "new_tool",
      description: "new",
      parameters: { type: "object", properties: {} },
    });
    nextContext.messages.push({
      role: "toolResult",
      toolCallId: "call_1",
      toolName: "read",
      content: [],
      addedToolNames: ["new_tool"],
      timestamp: 2,
      isError: false,
    });
    await exchange.create(
      [{ type: "function_call_output", call_id: "call_1", output: "ready" }],
      "r1",
      nextContext,
    );
    assert.equal(hooks, 2);
    assert.equal(socket.sent.at(-1).reasoning.effort, "high");
    assert.equal(
      socket.sent.at(-1).tools.find((tool) => tool.name === "new_tool").async,
      true,
    );
    assert.equal(exchange.advertisedAsyncToolNames.has("new_tool"), true);
    assert.equal(exchange.responseOptions.serviceTier, "priority");
    assert.equal(socket.sent.at(-1).input.length, 1);
    exchange.close();
  });
});

test("marks namespaced client tools but rejects invalid final hook output", async () => {
  await withFakeSocket(async () => {
    const exchange = await createOpenAICodexExchange(model(), context(), {
      apiKey: token(),
      openAICapabilities: { asyncTools: true, steering: true },
      onPayload: (body) => ({
        ...body,
        tools: [{ type: "namespace", name: "functions", tools: body.tools }],
      }),
    });
    await exchange.create();
    assert.equal(
      FakeWebSocket.instances[0].sent[0].tools[0].tools[0].async,
      true,
    );
    exchange.close();
    for (const transform of [
      () => null,
      (body) => ({ ...body, tools: [{ ...body.tools[0], async: "true" }] }),
      (body) => ({ ...body, tools: [{ ...body.tools[0], async: false }] }),
      (body) => ({
        ...body,
        tools: [{ ...body.tools[0], name: "unregistered" }],
      }),
    ]) {
      await assert.rejects(
        createOpenAICodexExchange(model(), context(), {
          apiKey: token(),
          openAICapabilities: { asyncTools: true, steering: true },
          onPayload: transform,
        }),
        /Invalid|unknown|not enabled/,
      );
    }
    assert.equal(FakeWebSocket.instances.length, 1);
  });
});

test("batched terminal frames cannot advance steering state ahead of the consumer", async () => {
  await withFakeSocket(async () => {
    const exchange = await createOpenAICodexExchange(model(), context(), {
      apiKey: token(),
      openAICapabilities: { asyncTools: true, steering: true },
    });
    await exchange.create();
    const socket = FakeWebSocket.instances[0];
    socket.event({ type: "response.created", response: { id: "r1" } });
    socket.event({ type: "response.completed", response: { id: "r1" } });
    await new Promise(setImmediate);
    const iterator = exchange.events[Symbol.asyncIterator]();
    await iterator.next();
    exchange.steer("r1", "near-terminal input");
    assert.equal(socket.sent.at(-1).type, "response.steer");
    await iterator.next();
    assert.throws(
      () => exchange.steer("r1", "already ended"),
      /active response/,
    );
    exchange.close();
  });
});

test("rejects a disconnected exchange without replaying a request", async () => {
  await withFakeSocket(async () => {
    const exchange = await createOpenAICodexExchange(model(), context(), {
      apiKey: token(),
      openAICapabilities: { asyncTools: false, steering: false },
    });
    const socket = FakeWebSocket.instances[0];
    exchange.create();
    const iterator = exchange.events[Symbol.asyncIterator]();
    socket.emit("close", { code: 1006, reason: "lost", wasClean: false });
    await assert.rejects(iterator.next(), /WebSocket closed 1006 lost/);
    assert.equal(socket.sent.length, 1);
  });
});
