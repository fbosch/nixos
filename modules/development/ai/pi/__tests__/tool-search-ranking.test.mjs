import assert from "node:assert/strict";
import { spawnSync } from "node:child_process";
import { mkdtemp, rm, writeFile } from "node:fs/promises";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { test } from "node:test";

const binary = process.env.PI_TEST_BINARY;
assert.ok(binary, "PI_TEST_BINARY must point to the compiled Pi executable");

const extension = `
import assert from "node:assert/strict";
import {
  createCodemodeExtension,
  createToolSearchExtension,
  installToolSearchRanker,
} from "@earendil-works/pi-coding-agent";

const parameterSchema = { type: "object", properties: {} };
const initialTools = [
  { name: "archive", description: "Archive old project reports", parameters: parameterSchema, exposure: "deferred", namespace: { name: "chosen", description: "Chosen source" } },
  { name: "blue", description: "Create a blue marker", parameters: parameterSchema, exposure: "deferred", namespace: { name: "chosen", description: "Chosen source" } },
  { name: "elsewhere", description: "Lookup another source", parameters: parameterSchema, exposure: "deferred", namespace: { name: "other", description: "Other source" } },
  { name: "activeArchive", description: "Already active item", parameters: parameterSchema, exposure: "deferred", namespace: { name: "chosen", description: "Chosen source" } },
  { name: "directArchive", description: "Direct item", parameters: parameterSchema, exposure: "direct", namespace: { name: "chosen", description: "Chosen source" } },
  { name: "modelArchive", description: "Model-only item", parameters: parameterSchema, exposure: "model-only", namespace: { name: "chosen", description: "Chosen source" } },
  { name: "codemodeArchive", description: "Deferred script item", parameters: parameterSchema, exposure: "codemode", namespace: { name: "chosen", description: "Chosen source" } },
];
const state = { tools: initialTools, active: ["activeArchive"], changes: [] };
let toolSearch;
const pi = {
  registerTool(definition) { toolSearch = definition; },
  getAllTools() { return state.tools; },
  getActiveTools() { return [...state.active]; },
  setActiveTools(names) { state.active = [...names]; state.changes.push([...names]); },
  appendEntry() {},
  getSettings() { return {}; },
};
createToolSearchExtension()(pi);
let codemode;
createCodemodeExtension({ models: false })({ ...pi, registerTool(definition) { codemode = definition; } });

function context(registry, label, signal) {
  return {
    modelRegistry: registry,
    label,
    signal,
    tools: state.tools.map((tool) => ({ ...tool, execute: async () => ({ content: [] }) })),
    sessionManager: { getBranch: () => [] },
  };
}
async function runSearch(registry, signal, query = "archive", limit = 2, globalSignal) {
  return toolSearch.execute("rank-test", { query, limit }, signal, undefined, context(registry, "tool_search", globalSignal));
}
async function runScript(registry, code, signal, globalSignal, timeoutMs = 10000) {
  return codemode.execute("rank-script", {
    code: '// @options: {"timeout_ms": ' + timeoutMs + '}\\n' + code,
  }, signal, undefined, context(registry, "codemode", globalSignal));
}
function usage() {
  return {
    input: 7,
    output: 2,
    cacheRead: 0,
    cacheWrite: 0,
    totalTokens: 9,
    cost: { input: 0.01, output: 0.02, cacheRead: 0, cacheWrite: 0, total: 0.03 },
  };
}
function gate() {
  let resolve;
  let markStarted;
  const started = new Promise((done) => { markStarted = done; });
  const pending = new Promise((done) => { resolve = done; });
  return { started, pending, resolve, markStarted };
}
function assertUsageFailure(result, pattern) {
  assert.equal(result.isError, true);
  assert.deepEqual(result.usage, usage());
  const text = result.content.map((item) => item.text ?? "").join("\\n");
  assert.match(text, pattern, text);
  return text;
}
function assertNativeUsageFailure(result, pattern) {
  assertUsageFailure(result, pattern);
  assert.deepEqual(result.details.loaded, []);
}
function resetState() {
  state.tools = initialTools;
  state.active = ["activeArchive"];
  state.changes = [];
}

export default async function () {
  const registry = {};
  let codemodeRequest;
  let nativeRequest;
  const unregister = installToolSearchRanker(registry, (request) => {
    if (request.context.label === "codemode") {
      codemodeRequest = request;
      assert.deepEqual(request.documents.map((document) => document.name), [
        "archive", "blue", "activeArchive", "directArchive", "modelArchive", "codemodeArchive",
      ]);
    } else {
      nativeRequest = request;
      assert.deepEqual(request.documents.map((document) => document.name), [
        "archive", "blue", "elsewhere", "codemodeArchive",
      ]);
    }
    assert.equal(request.documents[0].description, "Archive old project reports");
    assert.ok(request.documents[0].text.includes("chosen"));
    const lexical = request.rankLexical(24);
    assert.ok(lexical.length > 0);
    assert.ok(lexical.every((match) => request.documents.some((document) => document.name === match.name)));
    assert.throws(() => request.rankLexical(0), /positive integer/);
    request.reportUsage(usage());
    assert.throws(() => request.reportUsage(usage()), /already reported/);
    return { matches: [{ name: "archive", score: 0.9 }], usage: usage() };
  });

  const scriptResult = await runScript(registry,
    'return await searchTools("archive", { namespace: "chosen" });');
  assert.notEqual(scriptResult.isError, true, scriptResult.content.map((item) => item.text ?? "").join("\\n"));
  assert.match(scriptResult.content.map((item) => item.text ?? "").join("\\n"), /archive/);
  assert.deepEqual(scriptResult.usage, usage());
  assert.equal(codemodeRequest.context.label, "codemode");
  assert.equal(state.changes.length, 0, "searchTools() must not activate tools");

  const nativeResult = await runSearch(registry);
  assert.deepEqual(nativeRequest.documents.map((document) => document.name), ["archive", "blue", "elsewhere", "codemodeArchive"]);
  assert.deepEqual(nativeResult.details.loaded, ["archive"]);
  assert.deepEqual(nativeResult.usage, usage());
  assert.deepEqual(state.active, ["activeArchive", "archive"], "tool_search adds without dropping active tools");
  unregister();

  async function rejectsUnsafeResult(result, pattern) {
    resetState();
    const localRegistry = {};
    const remove = installToolSearchRanker(localRegistry, () => result);
    const before = [...state.active];
    const changes = state.changes.length;
    await assert.rejects(runSearch(localRegistry), pattern);
    assert.deepEqual(state.active, before);
    assert.equal(state.changes.length, changes);
    remove();
  }
  await rejectsUnsafeResult({ matches: [{ name: "directArchive", score: 1 }] }, /unknown candidate/);
  await rejectsUnsafeResult({ matches: [{ name: "archive", score: 1 }, { name: "archive", score: 0.5 }] }, /duplicate candidate/);
  await rejectsUnsafeResult({ matches: [{ name: "archive", score: Number.NaN }] }, /invalid score/);
  await rejectsUnsafeResult({ matches: [{ name: "archive", score: 1 }, { name: "blue", score: 0.5 }, { name: "codemodeArchive", score: 0.2 }] }, /requested limit/);

  const replacementRegistry = {};
  let originalCalls = 0;
  let replacementCalls = 0;
  const removeOriginal = installToolSearchRanker(replacementRegistry, () => {
    originalCalls++;
    return { matches: [] };
  });
  const removeReplacement = installToolSearchRanker(replacementRegistry, () => {
    replacementCalls++;
    return { matches: [{ name: "archive", score: 0.8 }] };
  });
  removeOriginal();
  removeOriginal();
  resetState();
  assert.deepEqual((await runSearch(replacementRegistry)).details.loaded, ["archive"]);
  assert.equal(originalCalls, 0);
  assert.equal(replacementCalls, 1);
  removeReplacement();
  removeReplacement();
  resetState();
  const fallbackResult = await runSearch(replacementRegistry);
  assert.ok(fallbackResult.details.loaded.includes("archive"), "native tool_search falls back to BM25");
  assert.equal(fallbackResult.usage, undefined);
  const changesBeforeScriptFallback = state.changes.length;
  const fallbackScript = await runScript(replacementRegistry,
    'return await searchTools("archive", { namespace: "chosen" });');
  assert.notEqual(fallbackScript.isError, true);
  assert.match(fallbackScript.content.map((item) => item.text ?? "").join("\\n"), /archive/);
  assert.equal(state.changes.length, changesBeforeScriptFallback, "fallback searchTools() remains non-activating");

  for (const signalSource of ["caller", "context"]) {
    for (const entryPoint of ["native", "codemode"]) {
      resetState();
      const localRegistry = {};
      const pending = gate();
      const remove = installToolSearchRanker(localRegistry, async (request) => {
        request.reportUsage(usage());
        pending.markStarted(request);
        return pending.pending;
      });
      const controller = new AbortController();
      const signal = signalSource === "caller" ? controller.signal : undefined;
      const globalSignal = signalSource === "context" ? controller.signal : undefined;
      const operation = entryPoint === "native"
        ? runSearch(localRegistry, signal, "archive", 2, globalSignal)
        : runScript(localRegistry, 'return await searchTools("archive");', signal, globalSignal);
      const request = await pending.started;
      controller.abort();
      assert.throws(() => request.rankLexical(24), /abort/i);
      pending.resolve({ matches: [{ name: "archive", score: 1 }], usage: usage() });
      const result = await operation;
      if (entryPoint === "native")
        assertNativeUsageFailure(result, /abort/i);
      else
        assertUsageFailure(result, /abort/i);
      assert.deepEqual(state.active, ["activeArchive"]);
      assert.equal(state.changes.length, 0);
      remove();
    }
  }

  for (const entryPoint of ["native", "codemode"]) {
    resetState();
    const localRegistry = {};
    const remove = installToolSearchRanker(localRegistry, (request) => {
      request.reportUsage(usage());
      throw Object.assign(new Error("ranker aborted"), { name: "AbortError" });
    });
    const result = entryPoint === "native"
      ? await runSearch(localRegistry)
      : await runScript(localRegistry, 'return await searchTools("archive");');
    if (entryPoint === "native")
      assertNativeUsageFailure(result, /abort/i);
    else
      assertUsageFailure(result, /abort/i);
    assert.deepEqual(state.active, ["activeArchive"]);
    assert.equal(state.changes.length, 0);
    remove();
  }

  for (const entryPoint of ["native", "codemode"]) {
    resetState();
    const localRegistry = {};
    const remove = installToolSearchRanker(localRegistry, () => ({
      matches: [{ name: "notRegistered", score: 1 }],
      usage: usage(),
    }));
    const result = entryPoint === "native"
      ? await runSearch(localRegistry)
      : await runScript(localRegistry, 'return await searchTools("archive");');
    if (entryPoint === "native")
      assertNativeUsageFailure(result, /unknown candidate/i);
    else
      assertUsageFailure(result, /unknown candidate/i);
    assert.deepEqual(state.active, ["activeArchive"]);
    assert.equal(state.changes.length, 0);
    remove();
  }

  resetState();
  {
    const localRegistry = {};
    const pending = gate();
    const remove = installToolSearchRanker(localRegistry, async (request) => {
      pending.markStarted(request);
      return pending.pending;
    });
    const operation = runSearch(localRegistry);
    await pending.started;
    state.tools = initialTools.map((tool) => tool.name === "archive" ? { ...tool, exposure: "direct" } : tool);
    state.active = ["activeArchive", "directArchive"];
    pending.resolve({
      matches: [{ name: "archive", score: 1 }, { name: "blue", score: 0.5 }],
      usage: usage(),
    });
    const result = await operation;
    assert.deepEqual(result.details.loaded, ["blue"]);
    assert.deepEqual(state.active, ["activeArchive", "directArchive", "blue"]);
    assert.deepEqual(result.usage, usage());
    remove();
  }

  for (const invalidation of ["unregister", "replace"]) {
    for (const entryPoint of ["native", "codemode"]) {
      resetState();
      const localRegistry = {};
      const pending = gate();
      const remove = installToolSearchRanker(localRegistry, async (request) => {
        pending.markStarted(request);
        return pending.pending;
      });
      const operation = entryPoint === "native"
        ? runSearch(localRegistry)
        : runScript(localRegistry, 'return await searchTools("archive");');
      await pending.started;
      let removeReplacement;
      if (invalidation === "unregister") {
        remove();
      } else {
        removeReplacement = installToolSearchRanker(localRegistry, () => ({ matches: [] }));
      }
      pending.resolve({ matches: [{ name: "archive", score: 1 }], usage: usage() });
      const result = await operation;
      if (entryPoint === "native")
        assertNativeUsageFailure(result, /unregistered or replaced/);
      else
        assertUsageFailure(result, /unregistered or replaced/);
      assert.deepEqual(state.active, ["activeArchive"]);
      assert.equal(state.changes.length, 0);
      removeReplacement?.();
    }
  }

  resetState();
  {
    const localRegistry = {};
    const pending = gate();
    const remove = installToolSearchRanker(localRegistry, async (request) => {
      pending.markStarted(request);
      return pending.pending;
    });
    const operation = runSearch(localRegistry);
    await pending.started;
    remove();
    pending.resolve({ matches: [{ name: "archive", score: 1 }] });
    await assert.rejects(operation, /unregistered or replaced/);
    assert.deepEqual(state.active, ["activeArchive"]);
    assert.equal(state.changes.length, 0);
  }

  for (const scenario of ["early-return", "timeout"]) {
    resetState();
    const localRegistry = {};
    let callAborted = false;
    const remove = installToolSearchRanker(localRegistry, async (request) => {
      assert.ok(request.signal, "codemode ranking must receive the sandbox call signal");
      await new Promise((resolve) => {
        const abort = () => {
          callAborted = true;
          resolve();
        };
        if (request.signal.aborted) {
          abort();
          return;
        }
        request.signal.addEventListener("abort", abort, { once: true });
      });
      return { matches: [] };
    });
    const code = scenario === "early-return"
      ? 'void searchTools("archive"); return "script finished";'
      : 'return await searchTools("archive");';
    const result = await runScript(localRegistry, code, undefined, undefined, scenario === "timeout" ? 500 : 2000);
    assert.equal(callAborted, true, "sandbox " + scenario + " must abort pending tool searches");
    if (scenario === "early-return")
      assert.notEqual(result.isError, true, "unawaited search must not delay script completion until timeout");
    if (scenario === "timeout")
      assert.equal(result.isError, true, "a timed-out sandbox script should report an error");
    remove();
  }
  console.log("PI_TOOL_SEARCH_RANKING_COMPILED_OK");
}
`;

test("compiled Pi binary exercises shared tool search ranking safely", async () => {
  const dir = await mkdtemp(join(tmpdir(), "pi-tool-search-ranking-"));
  try {
    const path = join(dir, "smoke.mjs");
    await writeFile(path, extension);
    const result = spawnSync(binary, [
      "--offline", "--no-extensions", "--no-skills", "--no-prompt-templates",
      "--no-context-files", "--no-themes", "--no-session", "-e", path, "--mode", "rpc",
    ], {
      cwd: dir,
      env: {
        HOME: dir,
        PATH: process.env.PATH,
        PI_CODING_AGENT_DIR: join(dir, "agent"),
        PI_OFFLINE: "1",
        PI_SKIP_VERSION_CHECK: "1",
        PI_TELEMETRY: "0",
      },
      encoding: "utf8",
      timeout: 30_000,
    });
    const output = `${result.stdout ?? ""}\n${result.stderr ?? ""}`;
    assert.ifError(result.error);
    assert.equal(result.status, 0, output);
    assert.match(output, /PI_TOOL_SEARCH_RANKING_COMPILED_OK/, output);
    assert.doesNotMatch(output, /Script sandbox failed|Cannot find module/, output);
  } finally {
    await rm(dir, { recursive: true, force: true });
  }
});
