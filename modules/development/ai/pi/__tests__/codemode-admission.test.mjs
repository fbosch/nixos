import assert from "node:assert/strict";
import { join } from "node:path";
import { setTimeout as delay } from "node:timers/promises";
import { pathToFileURL } from "node:url";
import { test } from "node:test";

const modulePath = process.env.PI_TEST_ADMISSION_MODULE
  ?? (process.env.PI_TEST_PACKAGE && join(process.env.PI_TEST_PACKAGE, "dist/extensions/codemode/worker-admission.js"));
assert.ok(modulePath, "PI_TEST_PACKAGE or PI_TEST_ADMISSION_MODULE must identify the patched admission module");
const { CodemodeWorkerAdmission, CodemodeAdmissionError, CODEMODE_WORKER_BUDGET_BYTES, createCodemodeResourceProbe } = await import(pathToFileURL(modulePath));
const GiB = 1024 ** 3;

function fixture(t, options = {}) {
  const resources = { availableMemory: 16 * GiB, totalMemory: 32 * GiB, parallelism: 64, cpuUtilization: 0 };
  const controller = new AbortController();
  const leases = [];
  const pending = [];
  let ceiling = options.ceiling;
  const pool = new CodemodeWorkerAdmission({
    resources: () => resources,
    ceiling: () => ceiling,
    retryMs: 10,
    ...options,
  });
  let nextId = 0;
  const acquire = (sessionId, extra = {}) => {
    const promise = pool.acquire({ sessionId, toolCallId: `call-${++nextId}`, timeoutMs: 1000, signal: controller.signal, ...extra })
      .then((lease) => { leases.push(lease); return lease; });
    pending.push(promise);
    return promise;
  };
  t.after(async () => {
    controller.abort();
    for (const lease of leases) lease.release();
    await Promise.allSettled(pending);
  });
  return { pool, resources, acquire, setCeiling: (value) => { ceiling = value; } };
}

test("idle pool allocates nothing and admits seven demanding sessions when resources permit", async (t) => {
  const f = fixture(t);
  assert.equal(f.pool.snapshot().activeWorkers, 0);
  const leases = await Promise.all(Array.from({ length: 7 }, (_, i) => f.acquire(`session-${i}`)));
  assert.equal(f.pool.snapshot().activeWorkers, 7);
  assert.equal(f.pool.snapshot().queuedRequests, 0);
  assert.ok(leases.every((lease) => lease.snapshot().resourceLimit > 7));
});

test("available memory determines the ceiling and reservations are counted before VM startup", async (t) => {
  const f = fixture(t);
  f.resources.availableMemory = GiB + 2 * CODEMODE_WORKER_BUDGET_BYTES;
  const first = await f.acquire("first");
  const second = await f.acquire("second");
  let admitted = false;
  const third = f.acquire("third").then((lease) => { admitted = true; return lease; });
  await delay(20);
  assert.equal(admitted, false);
  assert.deepEqual(f.pool.snapshot(), { activeWorkers: 2, queuedRequests: 1, resourceLimit: 2 });
  first.release();
  await third;
  assert.equal(f.pool.snapshot().activeWorkers, 2);
  assert.equal(second.snapshot().releasedAt, undefined);
});

test("memory pressure stops new admission without terminating holders", async (t) => {
  const f = fixture(t);
  const a = await f.acquire("a");
  const b = await f.acquire("b");
  f.resources.availableMemory = GiB + CODEMODE_WORKER_BUDGET_BYTES;
  let admitted = false;
  const c = f.acquire("c").then((lease) => { admitted = true; return lease; });
  await delay(20);
  assert.equal(f.pool.snapshot().activeWorkers, 2);
  assert.equal(a.snapshot().releasedAt, undefined);
  a.release();
  await delay(20);
  assert.equal(admitted, false);
  b.release();
  assert.equal((await c).snapshot().resourceLimit, 1);
});

test("resource recovery wakes a blocked queue without another request or worker exit", async (t) => {
  const f = fixture(t);
  f.resources.availableMemory = 0;
  const pending = f.acquire("waiting");
  assert.equal(f.pool.snapshot().activeWorkers, 0);
  assert.equal(f.pool.snapshot().queuedRequests, 1);
  f.resources.availableMemory = 8 * GiB;
  const lease = await pending;
  assert.ok(lease.snapshot().waitMs >= 0);
  assert.equal(f.pool.snapshot().queuedRequests, 0);
});

test("sustained CPU pressure serializes admission but still permits progress", async (t) => {
  const f = fixture(t);
  f.resources.cpuUtilization = 0.95;
  const first = await f.acquire("first");
  let admitted = false;
  const second = f.acquire("second").then((lease) => { admitted = true; return lease; });
  await delay(20);
  assert.equal(admitted, false);
  first.release();
  await second;
  assert.equal(f.pool.snapshot().activeWorkers, 1);
});

test("low-CPU I/O holders can grow beyond the logical CPU count", async (t) => {
  const f = fixture(t);
  f.resources.parallelism = 1;
  const leases = await Promise.all([f.acquire("a"), f.acquire("b"), f.acquire("c")]);
  assert.equal(leases.length, 3);
  assert.equal(f.pool.snapshot().activeWorkers, 3);
});

test("a session without a holder may bypass once, but cannot starve the oldest waiter", async (t) => {
  const f = fixture(t, { ceiling: () => 2 });
  const a = await f.acquire("a");
  const b = await f.acquire("b");
  const order = [];
  const a2 = f.acquire("a").then((lease) => { order.push("a"); return lease; });
  const c = f.acquire("c").then((lease) => { order.push("c"); return lease; });
  b.release();
  const cLease = await c;
  assert.deepEqual(order, ["c"]);
  const d = f.acquire("d").then((lease) => { order.push("d"); return lease; });
  cLease.release();
  (await a2).release();
  await d;
  assert.deepEqual(order, ["c", "a", "d"]);
  assert.equal(a.snapshot().releasedAt, undefined);
});

test("abort removes a waiter without consuming or releasing another request's slot", async (t) => {
  const f = fixture(t, { ceiling: () => 1 });
  const holder = await f.acquire("holder");
  const controller = new AbortController();
  const waiting = f.acquire("waiting", { signal: controller.signal });
  controller.abort();
  await assert.rejects(waiting, (error) => error instanceof CodemodeAdmissionError && error.reason === "aborted");
  assert.equal(f.pool.snapshot().activeWorkers, 1);
  assert.equal(f.pool.snapshot().queuedRequests, 0);
  holder.release();
  await f.acquire("next");
});

test("timeout leaves held workers intact and does not block subsequent admission", async (t) => {
  const f = fixture(t, { ceiling: () => 1 });
  const holder = await f.acquire("holder");
  await assert.rejects(f.acquire("waiting", { timeoutMs: 10 }), (error) => {
    assert.equal(error.reason, "timeout");
    assert.equal(error.details.admittedAt, undefined);
    return true;
  });
  assert.equal(f.pool.snapshot().activeWorkers, 1);
  holder.release();
  await f.acquire("next");
});

test("lease lifecycle reports actual release and double release is harmless", async (t) => {
  const f = fixture(t);
  const events = [];
  const lease = await f.acquire("owner", { onEvent: (event) => events.push(event) });
  lease.started();
  assert.deepEqual(events.map((event) => event.kind), ["queued", "admitted", "started"]);
  assert.equal(lease.snapshot().releasedAt, undefined);
  lease.release();
  lease.release();
  assert.deepEqual(events.map((event) => event.kind), ["queued", "admitted", "started", "released"]);
  assert.equal(f.pool.snapshot().activeWorkers, 0);
  assert.ok(events.at(-1).releasedAt >= events.at(-1).startedAt);
});

test("zero deadline never admits even when a worker could start immediately", async (t) => {
  const f = fixture(t);
  await assert.rejects(f.acquire("expired", { timeoutMs: 0 }), (error) => error.reason === "timeout");
  assert.equal(f.pool.snapshot().activeWorkers, 0);
});

test("invalid probes reject explicitly and clean the queue", async (t) => {
  const f = fixture(t);
  f.resources.parallelism = 0;
  await assert.rejects(f.acquire("invalid"), /Invalid codemode worker resource/);
  assert.equal(f.pool.snapshot().queuedRequests, 0);
  assert.equal(f.pool.snapshot().activeWorkers, 0);
});

test("the environment ceiling remains live and rejects malformed values", async (t) => {
  const previous = process.env.PI_CODEMODE_MAX_WORKERS;
  t.after(() => {
    if (previous === undefined) delete process.env.PI_CODEMODE_MAX_WORKERS;
    else process.env.PI_CODEMODE_MAX_WORKERS = previous;
  });
  process.env.PI_CODEMODE_MAX_WORKERS = "1";
  const f = fixture(t, { ceiling: undefined });
  const first = await f.acquire("first");
  const second = f.acquire("second");
  assert.equal(f.pool.snapshot().queuedRequests, 1);
  process.env.PI_CODEMODE_MAX_WORKERS = "2";
  const third = f.acquire("third");
  await second;
  assert.equal(f.pool.snapshot().activeWorkers, 2);
  first.release();
  (await third).release();
  process.env.PI_CODEMODE_MAX_WORKERS = "invalid";
  await assert.rejects(f.acquire("invalid"), /must be a positive safe integer/);
});

test("a telemetry error is visible but cannot leak a slot", async (t) => {
  const f = fixture(t);
  const warnings = [];
  t.mock.method(process, "emitWarning", (warning) => warnings.push(warning));
  const lease = await f.acquire("owner", { onEvent: () => { throw new Error("fixture telemetry failure"); } });
  lease.release();
  assert.equal(f.pool.snapshot().activeWorkers, 0);
  assert.ok(warnings.length >= 3);
});

test("the host resource probe produces bounded CPU and available-memory measurements", () => {
  const probe = createCodemodeResourceProbe();
  for (const resources of [probe(), probe()]) {
    assert.ok(Number.isFinite(resources.availableMemory) && resources.availableMemory >= 0);
    assert.ok(resources.totalMemory > 0);
    assert.ok(Number.isInteger(resources.parallelism) && resources.parallelism > 0);
    assert.ok(resources.cpuUtilization >= 0 && resources.cpuUtilization <= 1);
  }
});
