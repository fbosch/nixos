import assert from "node:assert/strict";
import { join } from "node:path";
import { setTimeout as delay } from "node:timers/promises";
import { pathToFileURL } from "node:url";
import { beforeEach, test } from "node:test";

const packageRoot = process.env.PI_TEST_PACKAGE;
assert.ok(packageRoot, "PI_TEST_PACKAGE must point to the patched Pi package");
const { executeCodemode } = await import(pathToFileURL(join(packageRoot, "dist/extensions/codemode/execute.js")));

// Stand in for the SDK host's event loop while awaiting unreferenced worker exit.
beforeEach((t) => {
  const lifetime = setTimeout(() => {}, 15000);
  t.after(() => clearTimeout(lifetime));
});

function deferred() {
  let resolve;
  const promise = new Promise((done) => { resolve = done; });
  return { promise, resolve };
}

function fixture(t, ceiling = "2") {
  const previous = process.env.PI_CODEMODE_MAX_WORKERS;
  process.env.PI_CODEMODE_MAX_WORKERS = ceiling;
  const releases = new Map();
  const events = [];
  let nextId = 0;
  let activeTools = 0;
  let peakTools = 0;
  t.after(() => {
    if (previous === undefined) delete process.env.PI_CODEMODE_MAX_WORKERS;
    else process.env.PI_CODEMODE_MAX_WORKERS = previous;
  });
  const run = async (code, options = {}) => {
    const id = `runtime-${++nextId}`;
    const released = deferred();
    releases.set(id, released.promise);
    const ctx = {
      tools: [{ name: "wait", description: "Fixture wait", parameters: { type: "object", properties: {} } }],
      sessionManager: { getBranch: () => [], getSessionId: () => options.sessionId ?? id },
      executeTool: async (_name, _args, { signal }) => {
        activeTools++;
        peakTools = Math.max(peakTools, activeTools);
        options.onToolStarted?.();
        try {
          if (options.block) await options.block;
          else await delay(30, undefined, { signal });
          return { toolCall: { id: `${id}/wait` }, isError: false, result: { content: [{ type: "text", text: "ok" }], details: {} } };
        } finally {
          activeTools--;
        }
      },
    };
    const result = await executeCodemode(id, { code }, options.signal, undefined, ctx, {
      onWorkerEvent: (event) => {
        events.push(event);
        if (event.kind === "released") released.resolve();
      },
    });
    return { id, result, released: released.promise };
  };
  return { run, events, peakTools: () => peakTools, releases };
}

test("real workers respect the process ceiling and report queue/start/exit timing", { timeout: 10000 }, async (t) => {
  const f = fixture(t);
  const runs = await Promise.all(Array.from({ length: 7 }, (_, i) => f.run("return await tools.wait({});", { sessionId: `session-${i}` })));
  await Promise.all(runs.map((run) => run.released));
  assert.ok(f.peakTools() <= 2);
  assert.ok(runs.some(({ result }) => result.details.admission.waitMs > 0));
  for (const { id, result } of runs) {
    assert.notEqual(result.isError, true, JSON.stringify(result));
    assert.equal(result.details.calls.length, 1);
    assert.equal(result.details.calls[0].status, "ok");
    const lifecycle = f.events.filter((event) => event.toolCallId === id);
    assert.deepEqual(lifecycle.map((event) => event.kind), ["queued", "admitted", "started", "released"]);
    assert.ok(lifecycle.at(-1).releasedAt >= lifecycle.at(-1).startedAt);
  }
});

test("queued cancellation and an exhausted deadline never start a worker", { timeout: 10000 }, async (t) => {
  const f = fixture(t, "1");
  const started = deferred();
  const blocker = deferred();
  const holder = f.run("return await tools.wait({});", { block: blocker.promise, onToolStarted: started.resolve });
  t.after(() => blocker.resolve());
  await started.promise;
  const controller = new AbortController();
  const cancelled = f.run("return 1;", { signal: controller.signal });
  controller.abort();
  const aborted = (await cancelled).result;
  assert.equal(aborted.isError, true);
  assert.equal(aborted.details.admission.admittedAt, undefined);
  const expired = (await f.run('// @options: {"timeout_ms": 15}\nreturn 2;')).result;
  assert.equal(expired.isError, true);
  assert.equal(expired.details.admission.startedAt, undefined);
  blocker.resolve();
  const completed = await holder;
  await completed.released;
  const next = await f.run("return 3;");
  assert.notEqual(next.result.isError, true, JSON.stringify(next.result));
  await next.released;
});

test("a running abort retains its reservation until actual exit and the next script still runs", { timeout: 10000 }, async (t) => {
  const f = fixture(t, "1");
  const started = deferred();
  const controller = new AbortController();
  const pending = f.run("return await tools.wait({});", { signal: controller.signal, onToolStarted: started.resolve });
  await started.promise;
  controller.abort();
  const aborted = await pending;
  assert.equal(aborted.result.isError, true);
  await aborted.released;
  const lifecycle = f.events.filter((event) => event.toolCallId === aborted.id);
  assert.equal(lifecycle.filter((event) => event.kind === "released").length, 1);
  assert.ok(lifecycle.at(-1).releasedAt >= lifecycle.at(-1).startedAt);
  const next = await f.run("return 4;");
  assert.notEqual(next.result.isError, true, JSON.stringify(next.result));
  await next.released;
});

test("a script exception does not leak the worker reservation", { timeout: 10000 }, async (t) => {
  const f = fixture(t, "1");
  const failed = await f.run('throw new Error("fixture error");');
  assert.equal(failed.result.isError, true);
  await failed.released;
  const next = await f.run("return 5;");
  assert.notEqual(next.result.isError, true, JSON.stringify(next.result));
  await next.released;
});


test("the SDK extension forwards worker lifecycle telemetry", { timeout: 10000 }, async () => {
  const { createCodemodeExtension } = await import(pathToFileURL(join(packageRoot, "dist/extensions/codemode/index.js")));
  const released = deferred();
  const events = [];
  let tool;
  createCodemodeExtension({ models: false, onWorkerEvent: (event) => {
    events.push(event);
    if (event.kind === "released") released.resolve();
  } })({
    registerTool: (definition) => { tool = definition; },
    getAllTools: () => [],
    getSettings: () => ({}),
    appendEntry() {},
  });
  const result = await tool.execute("sdk-admission", { code: "return 42;" }, undefined, undefined, {
    tools: [], sessionManager: { getBranch: () => [], getSessionId: () => "sdk-session" },
  });
  assert.notEqual(result.isError, true, JSON.stringify(result));
  await released.promise;
  assert.deepEqual(events.map((event) => event.kind), ["queued", "admitted", "started", "released"]);
  assert.ok(events.every((event) => event.sessionId === "sdk-session"));
});
