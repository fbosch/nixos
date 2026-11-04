import assert from "node:assert/strict";
import { spawnSync } from "node:child_process";
import { availableParallelism, totalmem } from "node:os";
import { join } from "node:path";
import { setTimeout as delay } from "node:timers/promises";
import { pathToFileURL } from "node:url";

// Controlled offline contention, not model latency or a replay of historical tool contents.
const baseline = process.env.PI_BENCH_BASE_PACKAGE;
const patched = process.env.PI_TEST_PACKAGE;
assert.ok(baseline && patched, "PI_BENCH_BASE_PACKAGE and PI_TEST_PACKAGE must identify baseline and patched packages");
const rounded = (value) => Math.round(value * 10) / 10;
const median = (values) => {
  const sorted = [...values].sort((a, b) => a - b);
  const mid = Math.floor(sorted.length / 2);
  return sorted.length % 2 ? sorted[mid] : (sorted[mid - 1] + sorted[mid]) / 2;
};
const percentile = (values, fraction) => [...values].sort((a, b) => a - b)[Math.ceil(values.length * fraction) - 1];

if (process.argv[2] !== "--child") {
  const trials = [];
  for (const mode of ["2", "4", "7", "adaptive", "adaptive", "7", "4", "2"]) {
    const env = { ...process.env, PI_OFFLINE: "1", PI_SKIP_VERSION_CHECK: "1", PI_TELEMETRY: "0" };
    if (mode === "adaptive") delete env.PI_CODEMODE_MAX_WORKERS;
    else env.PI_CODEMODE_MAX_WORKERS = mode;
    const child = spawnSync(process.execPath, [process.argv[1], "--child", mode], {
      env, encoding: "utf8", timeout: 60000, maxBuffer: 1024 * 1024,
    });
    assert.ifError(child.error);
    assert.equal(child.status, 0, child.stderr || child.stdout);
    const trial = JSON.parse(child.stdout);
    trials.push(trial);
    console.log(JSON.stringify({ type: "trial", ...trial }));
  }
  const summaries = ["2", "4", "7", "adaptive"].map((mode) => {
    const matching = trials.filter((trial) => trial.mode === mode);
    const workloads = {};
    for (const name of ["singleAgent", "sevenAgentsIo", "sevenAgentsCpu", "interactiveFairness"]) {
      const samples = matching.flatMap((trial) => trial.workloads[name] ?? []);
      if (!samples.length) continue;
      const starts = samples.flatMap((sample) => sample.firstToolStartMs);
      const queues = samples.flatMap((sample) => sample.queueWaitMs);
      const parent = samples.flatMap((sample) => sample.parentLatencyMs === undefined ? [] : [sample.parentLatencyMs]);
      workloads[name] = {
        samples: samples.length,
        medianMs: rounded(median(samples.map((sample) => sample.durationMs))),
        minMs: Math.min(...samples.map((sample) => sample.durationMs)),
        maxMs: Math.max(...samples.map((sample) => sample.durationMs)),
        toolConcurrency: [...new Set(samples.map((sample) => sample.peakTools))],
        workerConcurrency: [...new Set(samples.flatMap((sample) => sample.peakWorkers === null ? [] : [sample.peakWorkers]))],
        firstToolStartP95Ms: starts.length ? rounded(percentile(starts, 0.95)) : null,
        admissionWaitP95Ms: queues.length ? rounded(percentile(queues, 0.95)) : null,
        parentLatencyMedianMs: parent.length ? rounded(median(parent)) : null,
      };
    }
    return { mode, workloads, processPeakRssMiB: matching.map((trial) => trial.processPeakRssMiB) };
  });
  console.log(JSON.stringify({ type: "summary", summaries }));
} else {
  const mode = process.argv[3];
  const adaptive = mode === "adaptive";
  // Unreferenced workers rely on the CLI's lifetime in production.
  const deadline = setTimeout(() => { throw new Error(`Benchmark child ${mode} exceeded 55s`); }, 55000);
  const packageRoot = adaptive ? patched : baseline;
  const { executeCodemode } = await import(pathToFileURL(join(packageRoot, "dist/extensions/codemode/execute.js")));
  let nextId = 0;
  const host = { node: process.version, platform: process.platform, arch: process.arch, parallelism: availableParallelism(), totalMemoryMiB: rounded(totalmem() / 1024 ** 2), availableMemoryMiB: rounded(process.availableMemory() / 1024 ** 2) };

  async function scenario(name) {
    const firstToolStarts = new Map();
    const admissionWaits = [];
    const released = new Map();
    const startedTools = new Map();
    let activeTools = 0;
    let peakTools = 0;
    let activeWorkers = 0;
    let peakWorkers = 0;
    let parentLatencyMs;
    const startedAt = performance.now();
    const run = (code, sessionId) => {
      const id = `bench-${++nextId}`;
      let resolveReleased;
      const exit = new Promise((resolve) => { resolveReleased = resolve; });
      if (adaptive) released.set(id, exit);
      let resolveToolStarted;
      startedTools.set(id, new Promise((resolve) => { resolveToolStarted = resolve; }));
      const context = {
        tools: [{ name: "wait", description: "Synthetic asynchronous wait", parameters: { type: "object", properties: { ms: { type: "number" } }, required: ["ms"] } }],
        sessionManager: { getBranch: () => [], getSessionId: () => sessionId },
        executeTool: async (name, args, { signal }) => {
          assert.equal(name, "wait");
          assert.ok(args.ms >= 0 && args.ms <= 1000);
          activeTools++;
          peakTools = Math.max(peakTools, activeTools);
          if (!firstToolStarts.has(id)) firstToolStarts.set(id, performance.now() - startedAt);
          resolveToolStarted();
          try {
            await delay(args.ms, undefined, { signal });
            return { toolCall: { id: `${id}/wait` }, isError: false, result: { content: [{ type: "text", text: "ok" }], details: {} } };
          } finally {
            activeTools--;
          }
        },
      };
      const result = executeCodemode(id, { code: '// @options: {"timeout_ms": 15000}\n' + code }, undefined, () => {}, context, {
        onWorkerEvent: (event) => {
          if (event.kind === "started") { activeWorkers++; peakWorkers = Math.max(peakWorkers, activeWorkers); }
          if (event.kind === "released") { if (event.startedAt !== undefined) activeWorkers--; resolveReleased(); }
        },
      }).then((result) => {
        assert.notEqual(result.isError, true, JSON.stringify(result));
        assert.ok(result.details.calls.every((call) => call.status === "ok"));
        if (result.details.admission) admissionWaits.push(result.details.admission.waitMs);
        return result;
      });
      return { id, result };
    };
    const waits = (ms) => `return await tools.wait({ ms: ${ms} });`;
    let results;
    if (name === "singleAgent") {
      results = await Promise.all([run('return await Promise.all(Array.from({ length: 4 }, () => tools.wait({ ms: 50 })));', "parent").result]);
      assert.equal(results[0].details.calls.length, 4);
    } else if (name === "sevenAgentsIo") {
      results = await Promise.all(Array.from({ length: 7 }, (_, i) => run(waits(500), `session-${i}`).result));
      assert.ok(results.every((result) => result.details.calls.length === 1));
      assert.ok(peakTools <= (adaptive ? 7 : Number(mode)));
    } else if (name === "sevenAgentsCpu") {
      results = await Promise.all(Array.from({ length: 7 }, (_, i) => run('const end = Date.now() + 100; while (Date.now() < end) {} return "done";', `session-${i}`).result));
      assert.ok(results.every((result) => result.details.calls.length === 0));
    } else if (name === "interactiveFairness") {
      process.env.PI_CODEMODE_MAX_WORKERS = "2";
      const a = run(waits(600), "background-a");
      const b = run(waits(120), "background-b");
      await Promise.all([startedTools.get(a.id), startedTools.get(b.id)]);
      const a2 = run(waits(400), "background-a");
      const requestedAt = performance.now();
      const parent = run(waits(20), "interactive-parent");
      const observedParent = parent.result.then((result) => { parentLatencyMs = performance.now() - requestedAt; return result; });
      results = await Promise.all([a.result, b.result, a2.result, observedParent]);
      assert.ok(peakTools <= 2);
      if (adaptive) delete process.env.PI_CODEMODE_MAX_WORKERS;
      else process.env.PI_CODEMODE_MAX_WORKERS = mode;
    } else {
      throw new Error(`Unknown workload ${name}`);
    }
    const durationMs = performance.now() - startedAt;
    if (adaptive) await Promise.all(released.values());
    assert.equal(activeTools, 0);
    if (adaptive) assert.equal(activeWorkers, 0);
    await delay(50);
    return {
      durationMs: rounded(durationMs), peakTools, peakWorkers: adaptive ? peakWorkers : null,
      firstToolStartMs: [...firstToolStarts.values()].map(rounded), queueWaitMs: admissionWaits.map(rounded),
      ...(parentLatencyMs === undefined ? {} : { parentLatencyMs: rounded(parentLatencyMs) }),
    };
  }

  const workloads = {};
  const names = ["singleAgent", "sevenAgentsIo", "sevenAgentsCpu", ...(["2", "adaptive"].includes(mode) ? ["interactiveFairness"] : [])];
  for (const name of names) {
    await scenario(name);
    workloads[name] = [];
    for (let i = 0; i < 3; i++) workloads[name].push(await scenario(name));
  }
  console.log(JSON.stringify({ mode, host, workloads, processPeakRssMiB: rounded(process.resourceUsage().maxRSS / 1024) }));
  clearTimeout(deadline);
}
