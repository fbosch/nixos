import assert from "node:assert/strict";
import test from "node:test";
import { join } from "node:path";
import { pathToFileURL } from "node:url";
const root = process.env.PI_NATIVE_TEST_ROOT;
if (!root) throw new Error("Set PI_NATIVE_TEST_ROOT to the patched Pi package");
const { Agent } = await import(
  pathToFileURL(
    join(root, "node_modules/@earendil-works/pi-agent-core/dist/agent.js"),
  ).href
);
const { AssistantMessageEventStream } = await import(
  pathToFileURL(join(root, "node_modules/@earendil-works/pi-ai/dist/index.js"))
    .href
);
const model = {
  id: "gpt",
  name: "gpt",
  api: "openai-codex-responses",
  provider: "openai-codex",
  baseUrl: "",
  reasoning: false,
  input: ["text"],
  cost: { input: 0, output: 0, cacheRead: 0, cacheWrite: 0 },
  contextWindow: 1000,
  maxTokens: 1000,
};
function deferred() {
  let resolve, reject;
  const promise = new Promise((a, b) => {
    resolve = a;
    reject = b;
  });
  return { promise, resolve, reject };
}
function result(text = "ok") {
  return { content: [{ type: "text", text }], details: {} };
}
const user = (text) => ({
  role: "user",
  content: [{ type: "text", text }],
  timestamp: 1,
});
function tool(name = "lookup", execute = async () => result(), extra = {}) {
  return {
    name,
    label: name,
    description: name,
    parameters: {
      type: "object",
      properties: { q: { type: "string" } },
      required: ["q"],
    },
    execute,
    ...extra,
  };
}
function call(id = "1", extra = {}) {
  return {
    type: "function_call",
    id: `fc${id}`,
    call_id: `call${id}`,
    name: "lookup",
    arguments: '{"q":"x"}',
    async: true,
    ...extra,
  };
}
class Exchange {
  queue = [];
  waiters = [];
  created = [];
  steered = [];
  closed = 0;
  observers = [];
  advertisedAsyncToolNames = new Set(["lookup", "serial", "other", "grammar"]);
  responseOptions = {};
  get events() {
    return this;
  }
  [Symbol.asyncIterator]() {
    return this;
  }
  next() {
    if (this.queue.length) return Promise.resolve(this.queue.shift());
    const d = deferred();
    this.waiters.push(d);
    return d.promise;
  }
  push(event) {
    const next = { done: false, value: event };
    const waiter = this.waiters.shift();
    if (waiter) waiter.resolve(next);
    else this.queue.push(next);
  }
  disconnect() {
    const next = { done: true };
    const waiter = this.waiters.shift();
    if (waiter) waiter.resolve(next);
    else this.queue.push(next);
  }
  async create(input, previousResponseId, context) {
    this.created.push({ input, previousResponseId, context });
    this.notify();
  }
  async steer(previousResponseId, input) {
    this.steered.push({ previousResponseId, input });
    this.notify();
    if (this.rejectSteer) throw new Error("send disconnected");
  }
  close() {
    this.closed++;
    this.disconnect();
  }
  notify() {
    for (const observer of this.observers) observer();
  }
  waitFor(predicate) {
    if (predicate()) return Promise.resolve();
    return new Promise((resolve) => {
      const observer = () => {
        if (predicate()) {
          this.observers = this.observers.filter((x) => x !== observer);
          resolve();
        }
      };
      this.observers.push(observer);
    });
  }
  start(id = "r1") {
    this.push({ type: "response.created", response: { id } });
  }
  added(item, index = 0) {
    this.push({
      type: "response.output_item.added",
      output_index: index,
      item,
    });
  }
  done(item, index = 0) {
    this.push({ type: "response.output_item.done", output_index: index, item });
  }
  end(id = "r1", reason) {
    this.push({
      type: reason ? "response.incomplete" : "response.completed",
      response: {
        id,
        status: reason ? "incomplete" : "completed",
        output: [],
        ...(reason ? { incomplete_details: { reason } } : {}),
      },
    });
  }
  answer(id) {
    this.start(id);
    this.done({
      type: "message",
      id: `msg-${id}`,
      content: [{ type: "output_text", text: "done" }],
    });
    this.end(id);
  }
}
function setup(options = {}) {
  const exchange = options.exchange ?? new Exchange();
  const events = [],
    waiters = [];
  const agent = new Agent({
    streamFn: () => {
      throw new Error("ordinary stream must not run");
    },
    initialState: { model, tools: options.tools ?? [tool()] },
    openAICapabilities: { asyncTools: true, steering: true },
    openAIExchange: async () => exchange,
    ...options,
  });
  agent.subscribe((event) => {
    events.push(event);
    for (const waiter of waiters) waiter();
  });
  const wait = (predicate) => {
    const found = () => events.find(predicate);
    if (found()) return Promise.resolve(found());
    return new Promise((resolve) =>
      waiters.push(() => {
        const event = found();
        if (event) resolve(event);
      }),
    );
  };
  return { exchange, agent, events, wait };
}
const checkpoint = (phase, callId) => (event) =>
  event.type === "openai_checkpoint" &&
  event.record.phase === phase &&
  (!callId || event.record.callId === callId);
const tick = () => new Promise((resolve) => setImmediate(resolve));

// Every response is manually released: tests prove tools start while the terminal is withheld.
test(
  "async admission preserves permission, argument mutations, updates and final hooks before terminal",
  { timeout: 3000 },
  async () => {
    const permission = deferred(),
      execution = deferred(),
      started = deferred();
    let executions = 0,
      after = 0;
    const s = setup({
      tools: [
        tool(
          "lookup",
          async (id, args, signal, update) => {
            executions++;
            assert.equal(id, "call1|fc1");
            assert.equal(args.q, "prepared-mutated");
            assert.equal(signal.aborted, false);
            update(result("working"));
            started.resolve();
            await execution.promise;
            return result("raw");
          },
          { prepareArguments: (args) => ({ q: `prepared-${args.q}` }) },
        ),
      ],
      beforeToolCall: async ({ args, assistantMessage }) => {
        assert.deepEqual(assistantMessage.content[0].arguments, { q: "x" });
        await permission.promise;
        args.q = "prepared-mutated";
      },
      afterToolCall: async () => {
        after++;
        return { content: result("final").content, details: { hook: true } };
      },
    });
    const run = s.agent.prompt("go");
    await s.exchange.waitFor(() => s.exchange.created.length === 1);
    s.exchange.start();
    s.exchange.added(call());
    s.exchange.done(call());
    const intent = (await s.wait(checkpoint("call_intent"))).record;
    assert.deepEqual(intent.assistant.content[0].arguments, { q: "x" });
    assert.equal(executions, 0);
    permission.resolve();
    await started.promise;
    assert.equal(s.exchange.created.length, 1);
    assert.equal(s.agent.state.isStreaming, true);
    await s.wait((event) => event.type === "tool_execution_update");
    execution.resolve();
    const complete = (await s.wait(checkpoint("call_complete"))).record;
    assert.equal(complete.result.content[0].text, "final");
    assert.equal(complete.payload[0].call_id, "call1");
    s.exchange.done(
      {
        type: "message",
        id: "later",
        content: [{ type: "output_text", text: "later text" }],
      },
      1,
    );
    s.exchange.end();
    await s.exchange.waitFor(() => s.exchange.created.length === 2);
    assert.equal(
      intent.assistant.content.length,
      1,
      "checkpoint is a deep emission-time snapshot",
    );
    assert.equal(s.exchange.created[1].input[0].output, "final");
    s.exchange.answer("r2");
    await run;
    assert.equal(executions, 1);
    assert.equal(after, 1);
    assert.equal(s.exchange.closed, 1);
    assert.equal(
      s.events.filter((event) => event.type === "tool_execution_start").length,
      1,
    );
    assert.equal(
      s.agent.state.messages.filter((message) => message.role === "toolResult")
        .length,
      1,
    );
  },
);

for (const malformed of [
  '{"q":"salvaged"',
  "[]",
  "null",
  "{} trailing",
  undefined,
]) {
  test(
    `strict JSON rejects ${malformed} with real call correlation`,
    { timeout: 3000 },
    async () => {
      let executions = 0;
      const s = setup({
        tools: [
          tool("lookup", async () => {
            executions++;
            return result();
          }),
        ],
      });
      const run = s.agent.prompt("go");
      await s.exchange.waitFor(() => s.exchange.created.length === 1);
      s.exchange.start();
      s.exchange.done(call("bad", { arguments: malformed }));
      const complete = (await s.wait(checkpoint("call_complete"))).record;
      assert.equal(complete.callId, "callbad|fcbad");
      assert.equal(complete.result.isError, true);
      assert.equal(executions, 0);
      s.exchange.end();
      await s.exchange.waitFor(() => s.exchange.created.length === 2);
      assert.equal(s.exchange.created[1].input[0].call_id, "callbad");
      s.exchange.answer("r2");
      await run;
    },
  );
}

test(
  "identical duplicate is reserved before asynchronous permission; conflict fails and drains execution",
  { timeout: 3000 },
  async () => {
    const permission = deferred();
    let permissions = 0,
      executions = 0;
    const s = setup({
      beforeToolCall: async () => {
        permissions++;
        await permission.promise;
      },
      tools: [
        tool("lookup", async () => {
          executions++;
          return result();
        }),
      ],
    });
    const run = s.agent.prompt("go");
    await s.exchange.waitFor(() => s.exchange.created.length === 1);
    s.exchange.start();
    s.exchange.done(call());
    await s.wait(checkpoint("call_intent"));
    s.exchange.done(call());
    await tick();
    assert.equal(permissions, 1);
    permission.resolve();
    await s.wait(checkpoint("call_complete"));
    s.exchange.done(call("1", { arguments: '{"q":"conflict"}' }));
    await run;
    assert.equal(executions, 1);
    assert.match(s.agent.state.errorMessage, /Conflicting duplicate/);
    assert.equal(
      s.agent.state.messages.filter((m) => m.role === "toolResult").length,
      1,
    );
    assert.equal(s.exchange.created.length, 1);
    assert.equal(s.exchange.closed, 1);
    assert.equal(s.agent.state.messages.at(-1).openAI.nonRetryable, true);
  },
);

test(
  "missing correlation id fails without inventing a tool result",
  { timeout: 3000 },
  async () => {
    const s = setup();
    const run = s.agent.prompt("go");
    await s.exchange.waitFor(() => s.exchange.created.length === 1);
    s.exchange.start();
    s.exchange.done(call("1", { call_id: undefined }));
    await run;
    assert.match(s.agent.state.errorMessage, /correlation id/);
    assert.equal(
      s.events.filter((e) => e.type === "tool_execution_start").length,
      0,
    );
  },
);

for (const sequential of [false, true]) {
  test(
    `${sequential ? "global sequential" : "per-tool exclusive"} scheduling uses source-order preflight and execution barriers`,
    { timeout: 3000 },
    async () => {
      const gates = [deferred(), deferred(), deferred()];
      const order = [],
        started = [deferred(), deferred(), deferred()];
      const tools = ["lookup", "serial", "other"].map((name, i) =>
        tool(
          name,
          async () => {
            order.push(`execute${i}`);
            started[i].resolve();
            await gates[i].promise;
            order.push(`end${i}`);
            return result();
          },
          i === 1 ? { executionMode: "sequential" } : {},
        ),
      );
      const s = setup({
        tools,
        toolExecution: sequential ? "sequential" : "parallel",
        beforeToolCall: async ({ toolCall }) => {
          order.push(
            `prepare${tools.findIndex((t) => t.name === toolCall.name)}`,
          );
        },
      });
      const run = s.agent.prompt("go");
      await s.exchange.waitFor(() => s.exchange.created.length === 1);
      s.exchange.start();
      const items = tools.map((t, i) => call(String(i), { name: t.name }));
      items.forEach((item, i) => s.exchange.added(item, i));
      s.exchange.done(items[2], 2);
      s.exchange.done(items[1], 1);
      await tick();
      assert.deepEqual(order, []);
      s.exchange.done(items[0], 0);
      await started[0].promise;
      await tick();
      assert.deepEqual(order, ["prepare0", "execute0"]);
      gates[0].resolve();
      await started[1].promise;
      await tick();
      assert.deepEqual(order, [
        "prepare0",
        "execute0",
        "end0",
        "prepare1",
        "execute1",
      ]);
      gates[1].resolve();
      await started[2].promise;
      gates[2].resolve();
      s.exchange.end();
      await s.exchange.waitFor(() => s.exchange.created.length === 2);
      assert.deepEqual(
        s.exchange.created[1].input.map((i) => i.call_id),
        ["call2", "call1", "call0"].sort(),
      );
      s.exchange.answer("r2");
      await run;
    },
  );
}

test(
  "parallel execution overlaps but permission preflight remains source ordered",
  { timeout: 3000 },
  async () => {
    const firstPermission = deferred(),
      executions = [deferred(), deferred()],
      release = deferred();
    const preflight = [];
    const s = setup({
      beforeToolCall: async ({ toolCall }) => {
        preflight.push(toolCall.id);
        if (toolCall.id === "call1|fc1") await firstPermission.promise;
      },
      tools: [
        tool("lookup", async (id) => {
          executions[id === "call1|fc1" ? 0 : 1].resolve();
          await release.promise;
          return result();
        }),
      ],
    });
    const run = s.agent.prompt("go");
    await s.exchange.waitFor(() => s.exchange.created.length === 1);
    s.exchange.start();
    s.exchange.done(call("1"), 0);
    s.exchange.done(call("2"), 1);
    await s.wait(checkpoint("call_intent"));
    await tick();
    assert.deepEqual(preflight, ["call1|fc1"]);
    firstPermission.resolve();
    await Promise.all(executions.map((d) => d.promise));
    assert.deepEqual(preflight, ["call1|fc1", "call2|fc2"]);
    assert.equal(s.exchange.created.length, 1);
    release.resolve();
    s.exchange.end();
    await s.exchange.waitFor(() => s.exchange.created.length === 2);
    s.exchange.answer("r2");
    await run;
  },
);

test(
  "sync/async mixed calls drain in source order; historical results are never resent; dynamic tools refresh",
  { timeout: 3000 },
  async () => {
    const executed = [];
    let refreshes = 0;
    const lookup = tool("lookup", async (id) => {
      executed.push(id);
      return { ...result(id), addedToolNames: ["other"] };
    });
    const other = tool("other", async (id) => {
      executed.push(id);
      return result(id);
    });
    const s = setup({
      tools: [lookup],
      prepareNextTurnWithContext: async ({ context }) => {
        refreshes++;
        return { context: { ...context, tools: [lookup, other] } };
      },
    });
    const run = s.agent.prompt("go");
    await s.exchange.waitFor(() => s.exchange.created.length === 1);
    s.exchange.start();
    s.exchange.done(call("1", { async: false }), 0);
    s.exchange.done(call("2"), 1);
    await tick();
    assert.deepEqual(executed, []);
    s.exchange.end();
    await s.exchange.waitFor(() => s.exchange.created.length === 2);
    assert.deepEqual(executed, ["call1|fc1", "call2|fc2"]);
    assert.equal(refreshes, 1);
    assert.deepEqual(
      s.exchange.created[1].context.tools.map((t) => t.name),
      ["lookup", "other"],
    );
    assert.deepEqual(
      s.exchange.created[1].input.map((i) => i.call_id),
      ["call1", "call2"],
    );
    s.exchange.start("r2");
    s.exchange.done(call("3", { name: "other" }));
    s.exchange.end("r2");
    await s.exchange.waitFor(() => s.exchange.created.length === 3);
    assert.deepEqual(
      s.exchange.created[2].input.map((i) => i.call_id),
      ["call3"],
    );
    s.exchange.answer("r3");
    await run;
    assert.equal(executed.length, 3);
  },
);

test(
  "namespace and custom grammar mappings preserve complete input and raw output ids",
  { timeout: 3000 },
  async () => {
    const exchange = new Exchange();
    exchange.responseOptions = {
      grammarToolInputProperties: new Map([["grammar", "source"]]),
    };
    const s = setup({
      exchange,
      tools: [
        tool(
          "grammar",
          async (id, args) => {
            assert.equal(args.source, "a -> b");
            return result();
          },
          {
            parameters: {
              type: "object",
              properties: { source: { type: "string" } },
              required: ["source"],
            },
          },
        ),
      ],
    });
    const run = s.agent.prompt("go");
    await exchange.waitFor(() => exchange.created.length === 1);
    exchange.start();
    exchange.done({
      type: "custom_tool_call",
      id: "item/raw",
      call_id: "raw:call/1",
      name: "grammar",
      namespace: "syntax",
      input: "a -> b",
      async: true,
    });
    const intent = (await s.wait(checkpoint("call_intent"))).record;
    assert.equal(intent.assistant.content[0].namespace, "syntax");
    assert.deepEqual(intent.assistant.content[0].arguments, {
      source: "a -> b",
    });
    exchange.end();
    await exchange.waitFor(() => exchange.created.length === 2);
    assert.equal(exchange.created[1].input[0].type, "custom_tool_call_output");
    assert.equal(exchange.created[1].input[0].call_id, "raw:call/1");
    exchange.answer("r2");
    await run;
  },
);

for (const terminal of [undefined, "steered"]) {
  test(
    `accepted steering waits for manual automatic successor after ${terminal ?? "completed"}; same-text follow-up stays separate`,
    { timeout: 3000 },
    async () => {
      const s = setup();
      let refreshes = 0;
      s.agent.prepareNextTurnWithContext = async () => {
        refreshes++;
      };
      const run = s.agent.prompt("go");
      await s.exchange.waitFor(() => s.exchange.created.length === 1);
      s.exchange.start();
      await s.wait(
        (e) => e.type === "message_start" && e.message.role === "assistant",
      );
      s.agent.steer(user("same"));
      s.agent.followUp(user("same"));
      await s.exchange.waitFor(() => s.exchange.steered.length === 1);
      assert.equal(s.agent.hasQueuedMessages(), true);
      assert.equal(
        s.agent.state.messages.filter((m) => m.role === "user").length,
        1,
      );
      s.exchange.push({ type: "response.steer.accepted" });
      await s.wait(checkpoint("steer_accepted"));
      s.exchange.end("r1", terminal);
      await s.wait((e) => e.type === "turn_end");
      await tick();
      assert.equal(s.agent.state.isStreaming, true);
      assert.equal(s.exchange.created.length, 1);
      assert.equal(refreshes, 0);
      assert.equal(
        s.agent.state.messages.filter((m) => m.role === "user").length,
        1,
        "accepted is not incorporated",
      );
      s.exchange.answer("r2");
      const incorporated = (await s.wait(checkpoint("steer_incorporated")))
        .record;
      await s.exchange.waitFor(() => s.exchange.created.length === 2);
      assert.equal(s.exchange.steered.length, 1);
      assert.equal(s.exchange.created[1].previousResponseId, "r2");
      const users = s.agent.state.messages.filter((m) => m.role === "user");
      assert.equal(users.length, 3);
      assert.equal(
        users[1].openAI.deliveryId,
        incorporated.messages[0].openAI.deliveryId,
      );
      assert.equal(users[1].openAI.responseId, "r2");
      assert.equal(users[2].openAI, undefined);
      s.exchange.answer("r3");
      await run;
      assert.equal(s.agent.hasQueuedMessages(), false);
      assert.equal(s.exchange.closed, 1);
      assert.equal(s.agent.nativeSteeringSink, undefined);
    },
  );
}

test(
  "steer.pending submits predecessor outputs with original settings without repeating steering",
  { timeout: 3000 },
  async () => {
    let refreshes = 0;
    const s = setup({
      prepareNextTurnWithContext: async () => {
        refreshes++;
      },
    });
    const run = s.agent.prompt("go");
    await s.exchange.waitFor(() => s.exchange.created.length === 1);
    s.exchange.start();
    s.exchange.done(call());
    await s.wait(checkpoint("call_complete"));
    s.agent.steer(user("change"));
    await s.exchange.waitFor(() => s.exchange.steered.length === 1);
    s.exchange.end();
    await s.wait((e) => e.type === "turn_end");
    s.exchange.push({ type: "response.steer.pending" });
    await s.exchange.waitFor(() => s.exchange.created.length === 2);
    assert.equal(s.exchange.created[1].previousResponseId, "r1");
    assert.equal(s.exchange.created[1].context, undefined);
    assert.equal(refreshes, 0);
    assert.deepEqual(
      s.exchange.created[1].input.map((i) => i.call_id),
      ["call1"],
    );
    assert.equal(s.exchange.steered.length, 1);
    s.exchange.answer("r2");
    await run;
    assert.equal(s.exchange.created.length, 2);
    assert.equal(s.agent.hasQueuedMessages(), false);
  },
);

for (const mode of ["rejected", "disconnect", "send-failure"]) {
  test(
    `${mode} preserves reserved steering and stable delivery id without resend`,
    { timeout: 3000 },
    async () => {
      const s = setup();
      if (mode === "send-failure") s.exchange.rejectSteer = true;
      const run = s.agent.prompt("go");
      await s.exchange.waitFor(() => s.exchange.created.length === 1);
      s.exchange.start();
      await s.wait(
        (e) => e.type === "message_start" && e.message.role === "assistant",
      );
      s.agent.steer(user("keep"));
      await s.exchange.waitFor(() => s.exchange.steered.length === 1);
      if (mode === "rejected")
        s.exchange.push({
          type: "response.steer.failed",
          error: { message: "denied" },
        });
      if (mode === "disconnect") s.exchange.disconnect();
      await run;
      assert.equal(s.agent.hasQueuedMessages(), false);
      assert.equal(s.exchange.steered.length, 1);
      assert.equal(s.exchange.closed, 1);
      const sent = s.events.find(checkpoint("steer_sent")).record;
      assert.equal(s.events.filter(checkpoint("steer_failed")).length, 1);
      const failed = s.events.filter(checkpoint("steer_failed")).at(-1).record;
      assert.equal(failed.status, mode === "rejected" ? "failed" : "uncertain");
      assert.deepEqual(
        await s.agent.createLoopConfig().getSteeringMessages(),
        [],
      );
      const queued = s.agent.steeringQueue.messages;
      assert.equal(queued.length, 1);
      assert.equal(queued[0].content[0].text, "keep");
      assert.equal(
        queued[0].openAI.deliveryId,
        sent.messages[0].openAI.deliveryId,
      );
      assert.equal(s.agent.state.messages.at(-1).openAI.nonRetryable, true);
      assert.equal(s.agent.nativeSteeringSink, undefined);
      const nextExchange = new Exchange();
      s.agent.openAIExchange = async () => nextExchange;
      const nextRun = s.agent.prompt("independent next request");
      await nextExchange.waitFor(() => nextExchange.created.length === 1);
      nextExchange.answer("next-response");
      await nextRun;
      assert.equal(nextExchange.steered.length, 0);
      assert.equal(nextExchange.created.length, 1);
      assert.equal(
        s.agent.steeringQueue.messages[0].openAI.deliveryId,
        sent.messages[0].openAI.deliveryId,
      );
    },
  );
}

for (const abort of [true, false]) {
  test(
    `${abort ? "abort" : "origin response failure"} cooperatively drains already-running tool and persists final outcome`,
    { timeout: 3000 },
    async () => {
      const started = deferred(),
        cancellation = deferred(),
        release = deferred();
      const s = setup({
        tools: [
          tool("lookup", async (_id, _args, signal) => {
            signal.addEventListener("abort", () => cancellation.resolve(), {
              once: true,
            });
            started.resolve();
            await release.promise;
            return result("side effect completed");
          }),
        ],
      });
      const run = s.agent.prompt("go");
      await s.exchange.waitFor(() => s.exchange.created.length === 1);
      s.exchange.start();
      s.exchange.done(call());
      await started.promise;
      if (abort) s.agent.abort();
      else
        s.exchange.push({
          type: "response.failed",
          response: {
            id: "r1",
            error: { message: "response failed after effect" },
          },
        });
      await cancellation.promise;
      assert.equal(s.agent.state.isStreaming, true);
      release.resolve();
      await run;
      const outcome = s.agent.state.messages.find(
        (m) => m.role === "toolResult",
      );
      assert.equal(outcome.content[0].text, "side effect completed");
      assert.equal(outcome.isError, false);
      assert.ok(s.events.find(checkpoint("call_complete")));
      assert.equal(s.exchange.created.length, 1);
      assert.equal(s.exchange.closed, 1);
      assert.equal(s.agent.state.messages.at(-1).openAI.nonRetryable, true);
    },
  );
}

test(
  "protocol error exits without a terminal or hanging parser",
  { timeout: 3000 },
  async () => {
    const s = setup();
    const run = s.agent.prompt("go");
    await s.exchange.waitFor(() => s.exchange.created.length === 1);
    s.exchange.start();
    s.exchange.push({ type: "error", message: "bad protocol" });
    await run;
    assert.match(s.agent.state.errorMessage, /bad protocol/);
    assert.equal(s.exchange.closed, 1);
  },
);

test(
  "native disabled preserves default stream and queue behavior",
  { timeout: 3000 },
  async () => {
    let requests = 0;
    const s = setup({
      openAICapabilities: undefined,
      streamFn: () => {
        requests++;
        const stream = new AssistantMessageEventStream();
        const output = {
          role: "assistant",
          content: [],
          api: model.api,
          provider: model.provider,
          model: model.id,
          usage: {},
          stopReason: "stop",
          timestamp: 1,
        };
        stream.push({ type: "start", partial: output });
        stream.push({ type: "done", reason: "stop", message: output });
        return stream;
      },
    });
    s.agent.steer(user("queued"));
    await s.agent.prompt("go");
    assert.equal(requests, 1);
    assert.equal(s.exchange.created.length, 0);
    assert.equal(s.agent.state.messages[1].content[0].text, "queued");
  },
);

test("native capabilities fail loudly without an exchange factory", async () => {
  const s = setup({ openAIExchange: undefined });
  await s.agent.prompt("go");
  assert.match(s.agent.state.errorMessage, /no openAIExchange factory/);
});

test(
  "blocked permission preserves error result and terminate without execution",
  { timeout: 3000 },
  async () => {
    let executed = false;
    const s = setup({
      beforeToolCall: async () => ({
        block: true,
        reason: "permission denied",
        terminate: true,
      }),
      tools: [
        tool("lookup", async () => {
          executed = true;
          return result();
        }),
      ],
    });
    const run = s.agent.prompt("go");
    await s.exchange.waitFor(() => s.exchange.created.length === 1);
    s.exchange.start();
    s.exchange.done(call());
    const complete = (await s.wait(checkpoint("call_complete"))).record;
    assert.equal(complete.result.isError, true);
    assert.match(complete.result.content[0].text, /permission denied/);
    s.exchange.end();
    await run;
    assert.equal(executed, false);
    assert.equal(s.exchange.created.length, 1);
    assert.equal(s.exchange.closed, 1);
  },
);

test(
  "partial calls at token limit cannot execute salvaged arguments",
  { timeout: 3000 },
  async () => {
    let executions = 0;
    const s = setup({
      tools: [
        tool("lookup", async () => {
          executions++;
          return result();
        }),
      ],
    });
    const run = s.agent.prompt("go");
    await s.exchange.waitFor(() => s.exchange.created.length === 1);
    s.exchange.start();
    s.exchange.added(call("1", { arguments: '{"q":"salvaged"', async: false }));
    s.exchange.end("r1", "max_output_tokens");
    await s.exchange.waitFor(() => s.exchange.created.length === 2);
    assert.equal(executions, 0);
    assert.equal(s.exchange.created[1].input[0].call_id, "call1");
    assert.match(
      s.agent.state.messages.find((m) => m.role === "toolResult").content[0]
        .text,
      /not completed/,
    );
    s.exchange.answer("r2");
    await run;
  },
);

test(
  "one unresolved steering group; input queued after acceptance waits for incorporation",
  { timeout: 3000 },
  async () => {
    const s = setup();
    const run = s.agent.prompt("go");
    await s.exchange.waitFor(() => s.exchange.created.length === 1);
    s.exchange.start();
    await s.wait(
      (e) => e.type === "message_start" && e.message.role === "assistant",
    );
    s.agent.steer(user("first"));
    await s.exchange.waitFor(() => s.exchange.steered.length === 1);
    s.agent.steer(user("second"));
    s.exchange.push({ type: "response.steer.accepted" });
    s.exchange.end();
    await s.wait((e) => e.type === "turn_end");
    await tick();
    assert.equal(s.exchange.steered.length, 1);
    assert.deepEqual(
      await s.agent.createLoopConfig().getSteeringMessages(),
      [],
    );
    s.exchange.start("r2");
    await s.exchange.waitFor(() => s.exchange.steered.length === 2);
    assert.equal(s.exchange.steered[1].previousResponseId, "r2");
    assert.equal(s.agent.hasQueuedMessages(), true);
    s.exchange.push({ type: "response.steer.accepted" });
    s.exchange.end("r2");
    s.exchange.answer("r3");
    await run;
    const inputs = s.agent.state.messages.filter((m) => m.role === "user");
    assert.deepEqual(
      inputs.map((m) => m.content[0].text),
      ["go", "first", "second"],
    );
    assert.notEqual(inputs[1].openAI.deliveryId, inputs[2].openAI.deliveryId);
    assert.equal(s.exchange.created.length, 1);
  },
);

test(
  "aborting accepted steering before successor preserves uncertain reservation",
  { timeout: 3000 },
  async () => {
    const s = setup();
    const run = s.agent.prompt("go");
    await s.exchange.waitFor(() => s.exchange.created.length === 1);
    s.exchange.start();
    await s.wait(
      (e) => e.type === "message_start" && e.message.role === "assistant",
    );
    s.agent.steer(user("keep"));
    await s.exchange.waitFor(() => s.exchange.steered.length === 1);
    s.exchange.push({ type: "response.steer.accepted" });
    s.exchange.end();
    await s.wait((e) => e.type === "turn_end");
    s.agent.abort();
    await run;
    assert.equal(s.agent.hasQueuedMessages(), false);
    assert.equal(s.agent.state.messages.at(-1).stopReason, "aborted");
    assert.deepEqual(
      await s.agent.createLoopConfig().getSteeringMessages(),
      [],
    );
    assert.equal(
      s.agent.steeringQueue.messages[0].openAI.deliveryStatus,
      "uncertain",
    );
    assert.equal(s.exchange.created.length, 1);
    assert.equal(s.exchange.closed, 1);
  },
);

test(
  "result submission failure preserves finalized effect and forbids implicit replay",
  { timeout: 3000 },
  async () => {
    const exchange = new Exchange();
    const baseCreate = exchange.create.bind(exchange);
    exchange.create = async (...args) => {
      await baseCreate(...args);
      if (args[0]) throw new Error("write uncertain");
    };
    const s = setup({ exchange });
    const run = s.agent.prompt("go");
    await exchange.waitFor(() => exchange.created.length === 1);
    exchange.start();
    exchange.done(call());
    exchange.end();
    await run;
    assert.equal(exchange.created.length, 2);
    assert.equal(
      s.agent.state.messages.filter((m) => m.role === "toolResult").length,
      1,
    );
    assert.equal(s.agent.state.messages.at(-1).openAI.nonRetryable, true);
    assert.match(s.agent.state.errorMessage, /write uncertain/);
    const sent = s.events.find(checkpoint("result_send")).record;
    assert.equal(sent.payload[0].call_id, "call1");
    assert.ok(sent.messages.some((m) => m.role === "toolResult"));
    assert.equal(exchange.closed, 1);
  },
);

test(
  "terminal-boundary steering is normal queued input, never sent to ended predecessor",
  { timeout: 3000 },
  async () => {
    const s = setup();
    s.agent.subscribe((event) => {
      if (
        event.type === "turn_end" &&
        event.message.openAI?.responseId === "r1"
      )
        s.agent.steer(user("boundary"));
    });
    const run = s.agent.prompt("go");
    await s.exchange.waitFor(() => s.exchange.created.length === 1);
    s.exchange.answer("r1");
    await s.exchange.waitFor(() => s.exchange.created.length === 2);
    assert.equal(s.exchange.steered.length, 0);
    assert.equal(s.exchange.created[1].input[0].role, "user");
    s.exchange.answer("r2");
    await run;
    assert.equal(s.agent.hasQueuedMessages(), false);
  },
);

test(
  "low-level native event stream settles on protocol failure with full outcomes",
  { timeout: 3000 },
  async () => {
    const { agentLoop } = await import(
      pathToFileURL(
        join(
          root,
          "node_modules/@earendil-works/pi-agent-core/dist/agent-loop.js",
        ),
      ).href
    );
    const exchange = new Exchange();
    const events = [];
    const stream = agentLoop(
      [user("go")],
      { messages: [], tools: [tool()] },
      {
        model,
        convertToLlm: (m) => m,
        openAICapabilities: { asyncTools: true, steering: false },
        openAIExchange: async () => exchange,
      },
    );
    const consuming = (async () => {
      for await (const event of stream) events.push(event);
      return stream.result();
    })();
    await exchange.waitFor(() => exchange.created.length === 1);
    exchange.start();
    exchange.push({ type: "error", message: "protocol" });
    const messages = await consuming;
    assert.equal(messages.at(-1).openAI.nonRetryable, true);
    assert.equal(events.at(-1).type, "agent_end");
    assert.equal(exchange.closed, 1);
  },
);
