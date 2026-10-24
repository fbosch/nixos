import assert from "node:assert/strict";
import { createRequire } from "node:module";
import { join } from "node:path";
import { test } from "node:test";
import { pathToFileURL } from "node:url";

const packageRoot = process.env.PI_TEST_PACKAGE;
assert.ok(packageRoot, "PI_TEST_PACKAGE must point to the installed Pi package");
const aiRoot = join(packageRoot, "../pi-ai");
const importAi = (path) => import(pathToFileURL(join(aiRoot, "dist", path)).href);
const { parseJsonWithRepair, parseStreamingJson, parseStreamingJsonWhileStreaming, parseToolCallArguments, repairJson } =
  await importAi("utils/json-parse.js");
const { normalizeContext } = await importAi("utils/transcript.js");

function toolCall(index = 0, args = {}) {
  return { type: "toolCall", id: `call_${index}`, name: "replace", arguments: args };
}

const context = normalizeContext({ messages: [{ role: "user", content: "Edit the file", timestamp: 0 }] });
const usage = {
  input: 1, output: 1, cacheRead: 0, cacheWrite: 0, totalTokens: 2,
  cost: { input: 0, output: 0, cacheRead: 0, cacheWrite: 0, total: 0 },
};

function model(api) {
  return {
    id: "test-model", name: "Parser fixture", api,
    provider: api === "bedrock-converse-stream" ? "amazon-bedrock" : api.split("-")[0],
    baseUrl: "https://pi-stream-test.invalid/v1", reasoning: false, input: ["text"],
    cost: { input: 0, output: 0, cacheRead: 0, cacheWrite: 0 }, contextWindow: 128000, maxTokens: 8192,
  };
}

function chunks(text) {
  return Array.from({ length: Math.ceil(text.length / 32) }, (_, i) => text.slice(i * 32, (i + 1) * 32));
}

function* interleave(inputs) {
  const parts = inputs.map(chunks);
  for (let offset = 0; offset < Math.max(...parts.map((part) => part.length)); offset++) {
    for (let index = 0; index < parts.length; index++) {
      if (offset < parts[index].length) yield { index, delta: parts[index][offset] };
    }
  }
}

function* eventsFor(api, inputs, finals) {
  if (api === "anthropic-messages") {
    yield { type: "message_start", message: { id: "msg_fixture", type: "message", role: "assistant", content: [], model: "test-model", usage: { input_tokens: 1, output_tokens: 0 } } };
    for (const index of inputs.keys()) {
      yield { type: "content_block_start", index, content_block: { type: "tool_use", id: `call_${index}`, name: "replace", input: {} } };
    }
    for (const { index, delta } of interleave(inputs)) {
      yield { type: "content_block_delta", index, delta: { type: "input_json_delta", partial_json: delta } };
    }
    for (const index of inputs.keys()) yield { type: "content_block_stop", index };
    yield { type: "message_delta", delta: { stop_reason: "tool_use", stop_sequence: null }, usage: { output_tokens: 1 } };
    yield { type: "message_stop" };
  } else if (api === "openai-responses") {
    const item = (index, args) => ({ type: "function_call", id: `fc_${index}`, call_id: `call_${index}`, name: "replace", arguments: args });
    for (const index of inputs.keys()) yield { type: "response.output_item.added", output_index: index, item: item(index, "") };
    for (const { index, delta } of interleave(inputs)) {
      yield { type: "response.function_call_arguments.delta", output_index: index, delta };
    }
    for (const index of inputs.keys()) {
      yield { type: "response.function_call_arguments.done", output_index: index, arguments: finals[index] };
      yield { type: "response.output_item.done", output_index: index, item: item(index, finals[index]) };
    }
    yield { type: "response.completed", response: { id: "resp_fixture", status: "completed", output: [] } };
  } else if (api === "pi-messages") {
    yield { type: "start" };
    for (const index of inputs.keys()) yield { type: "toolcall_start", contentIndex: index, id: `call_${index}`, toolName: "replace" };
    for (const { index, delta } of interleave(inputs)) yield { type: "toolcall_delta", contentIndex: index, delta };
    for (const index of inputs.keys()) {
      yield { type: "toolcall_end", contentIndex: index, toolCall: { ...toolCall(index), ...parseToolCallArguments(finals[index]) } };
    }
    yield { type: "done", reason: "toolUse", usage };
  } else if (api === "bedrock-converse-stream") {
    yield { messageStart: { role: "assistant" } };
    for (const index of inputs.keys()) {
      yield { contentBlockStart: { contentBlockIndex: index, start: { toolUse: { toolUseId: `call_${index}`, name: "replace" } } } };
    }
    for (const { index, delta } of interleave(inputs)) {
      yield { contentBlockDelta: { contentBlockIndex: index, delta: { toolUse: { input: delta } } } };
    }
    for (const index of inputs.keys()) yield { contentBlockStop: { contentBlockIndex: index } };
    yield { messageStop: { stopReason: "tool_use" } };
    yield { metadata: { usage: { inputTokens: 1, outputTokens: 1, totalTokens: 2 }, metrics: { latencyMs: 1 } } };
  } else {
    const chunk = (tool_calls, finish_reason = null) => ({
      id: "chatcmpl_fixture", object: "chat.completion.chunk", created: 0, model: "test-model",
      choices: [{ index: 0, delta: { tool_calls }, finish_reason }],
    });
    for (const index of inputs.keys()) {
      yield chunk([{ index, id: `call_${index}`, type: "function", function: { name: "replace", arguments: "" } }]);
    }
    for (const { index, delta } of interleave(inputs)) {
      yield chunk([{ index, function: { arguments: delta } }]);
    }
    yield chunk([], "tool_calls");
  }
}

async function runProvider(t, api, inputs, finals = inputs) {
  const { stream } = await importAi(`api/${api}.js`);
  const events = [...eventsFor(api, inputs, finals)];
  let requests = 0;
  if (api === "bedrock-converse-stream") {
    const require = createRequire(join(aiRoot, "package.json"));
    const { BedrockRuntimeClient } = require("@aws-sdk/client-bedrock-runtime");
    const send = BedrockRuntimeClient.prototype.send;
    BedrockRuntimeClient.prototype.send = async function () {
      requests++;
      return { $metadata: {}, stream: (async function* () { yield* events; })() };
    };
    t.after(() => { BedrockRuntimeClient.prototype.send = send; });
  }
  const eventStream = stream(model(api), context, {
    apiKey: "fixture-key", region: "us-east-1", env: {},
    fetch: async (input) => {
      assert.equal(new URL(typeof input === "string" ? input : input.url ?? input.href).hostname, "pi-stream-test.invalid");
      requests++;
      const body = events.map((event) =>
        (api === "anthropic-messages" ? `event: ${event.type}\n` : "") + `data: ${JSON.stringify(event)}\n\n`,
      ).join("") + "data: [DONE]\n\n";
      return new Response(body, { headers: { "Content-Type": "text/event-stream" } });
    },
    // Let consumers observe each preview before the provider mutates the shared message again.
    onProviderStreamEvent: () => new Promise((resolve) => setImmediate(resolve)),
  });
  const deltas = inputs.map(() => []);
  const previews = inputs.map(() => []);
  const ended = [];
  for await (const event of eventStream) {
    if (event.type === "toolcall_delta") {
      deltas[event.contentIndex].push(event.delta);
      previews[event.contentIndex].push(event.partial.content[event.contentIndex].arguments);
    } else if (event.type === "toolcall_end") {
      ended.push(structuredClone(event.toolCall));
    }
  }
  const result = await eventStream.result();
  assert.equal(requests, 1);
  assert.equal(result.stopReason, "toolUse", result.errorMessage);
  assert.deepEqual(deltas.map((parts) => parts.join("")), inputs, "raw delta events remain lossless and ordered");
  assert.equal(ended.length, inputs.length);
  return { result, ended, previews };
}

test("repairs every raw control character without corrupting surrounding Unicode", () => {
  for (let code = 0; code <= 0x1f; code++) {
    const raw = '{"before":"æøå","text":"left' + String.fromCharCode(code) + 'right","after":true}';
    const expected = { before: "æøå", text: `left${String.fromCharCode(code)}right`, after: true };
    assert.deepEqual(parseJsonWithRepair(raw), expected);
    assert.deepEqual(parseStreamingJson(raw), expected);
    assert.deepEqual(parseToolCallArguments(raw), { arguments: expected });
  }
});

test("preserves valid escapes and repairs literal backslashes, including invalid Unicode escapes", () => {
  const valid = { text: 'æøå café 😀\n\t\\\"', nested: [true, false, null, 2.5] };
  const json = JSON.stringify(valid);
  assert.equal(repairJson(json), json);
  assert.deepEqual(parseStreamingJson(json), valid);
  const raw = String.raw`{"path":"C:\project\dir","text":"\url{x} \usepackage{x} caf\u00e9","after":true}`;
  const expected = { path: String.raw`C:\project\dir`, text: "\\url{x} \\usepackage{x} café", after: true };
  assert.deepEqual(parseStreamingJson(raw), expected);
  assert.deepEqual(parseToolCallArguments(raw), { arguments: expected });
  assert.equal(repairJson('  \n{"text":"æøå"}\t'), '  \n{"text":"æøå"}\t');
  assert.equal(repairJson('"tail\\'), '"tail\\\\');
});

test("keeps incomplete previews lenient and final arguments strict", () => {
  assert.deepEqual(parseStreamingJson(String.raw`{"text":"ab\u00`), { text: "ab" });
  assert.deepEqual(parseStreamingJson('{"items":[{"ok":true},'), { items: [{ ok: true }] });
  for (const input of [undefined, "", " \r\n\t"]) {
    assert.deepEqual(parseStreamingJson(input), {});
    assert.deepEqual(parseToolCallArguments(input), { arguments: {} });
  }
  for (const input of ['{"text":"cut off', '{"action":"apply","time":.5}', "[]", "null", "42", '"text"']) {
    const result = parseToolCallArguments(input);
    assert.deepEqual(result.arguments, {});
    assert.ok(result.argumentsError.endsWith(input), result.argumentsError);
  }
});

test("updates small previews eagerly and bounds large-preview reparsing", () => {
  assert.equal(typeof parseStreamingJsonWhileStreaming, "function");
  const block = toolCall();
  const small = '{"text":"abc';
  let current;
  for (let end = 1; end <= small.length; end++) {
    current = parseStreamingJsonWhileStreaming(block, small.slice(0, end), current);
    assert.deepEqual(current, parseStreamingJson(small.slice(0, end)));
  }
  const raw = JSON.stringify({ text: "x".repeat(200 * 1024), tail: "æøå" });
  const large = toolCall();
  current = undefined;
  let updates = 0;
  let parsedCharacters = 0;
  for (let end = 16; end < raw.length + 16; end += 16) {
    const prefix = raw.slice(0, end);
    const next = parseStreamingJsonWhileStreaming(large, prefix, current);
    if (next !== current) { updates++; parsedCharacters += prefix.length; }
    current = next;
  }
  assert.ok(updates > 64 && updates <= 128, `${updates} reparses`);
  assert.ok(parsedCharacters <= 10 * raw.length + 65536, `${parsedCharacters} cumulative characters parsed`);
  assert.deepEqual(parseToolCallArguments(raw), { arguments: { text: "x".repeat(200 * 1024), tail: "æøå" } });
});

test("isolates interleaved calls and repeated IDs without mutating earlier snapshots", () => {
  const first = toolCall();
  const second = toolCall();
  const prefix = '{"text":"' + "x".repeat(2048);
  const snapshot = parseStreamingJsonWhileStreaming(first, prefix);
  assert.strictEqual(parseStreamingJsonWhileStreaming(first, prefix + "tail", snapshot), snapshot);
  assert.deepEqual(parseStreamingJsonWhileStreaming(second, '{"path":"æøå"}', {}), { path: "æøå" });
  const next = parseStreamingJsonWhileStreaming(first, prefix + "y".repeat(512), snapshot);
  assert.equal(next.text.length, 2560);
  assert.equal(snapshot.text, "x".repeat(2048));
  assert.deepEqual(parseStreamingJsonWhileStreaming(first, '{"reset":true}', next), { reset: true });
});

for (const api of ["openai-completions", "openai-responses", "anthropic-messages", "bedrock-converse-stream", "mistral-conversations", "pi-messages"]) {
  test(`${api}: preserves interleaved raw deltas and exact final arguments`, { timeout: 30000 }, async (t) => {
    const expected = [
      { path: "first.txt", text: "æøå " + "x".repeat(8192), tail: "last first" },
      { path: "second.txt", text: "y".repeat(4096), nested: { tail: "last second" } },
    ];
    const { result, ended, previews } = await runProvider(t, api, expected.map((args) => JSON.stringify(args)));
    assert.deepEqual(result.content.map((call) => call.arguments), expected);
    assert.deepEqual(ended.map((call) => call.arguments), expected);
    for (const [index, snapshots] of previews.entries()) {
      assert.ok(new Set(snapshots).size < snapshots.length / 2, "large streamed previews are coalesced");
      const partial = snapshots.find((args) => typeof args.text === "string" && args.text.length > 1024 && args.text.length < expected[index].text.length);
      assert.ok(partial, "large in-progress previews remain visible");
      assert.ok(expected[index].text.startsWith(partial.text));
    }
  });

  test(`${api}: reports malformed final arguments rather than reusing a cached prefix`, { timeout: 30000 }, async (t) => {
    const raw = JSON.stringify({ path: "file.txt", text: "x".repeat(4096) }).slice(0, -2);
    const { result, ended } = await runProvider(t, api, [raw]);
    assert.deepEqual(result.content[0].arguments, {});
    assert.ok(result.content[0].argumentsError.endsWith(raw));
    assert.deepEqual(ended[0].arguments, {});
    assert.ok(ended[0].argumentsError.endsWith(raw));
  });
}

test("OpenAI Responses uses authoritative done arguments even for a same-length replacement", async (t) => {
  const first = JSON.stringify({ text: "x".repeat(4096), tail: "old" });
  const final = JSON.stringify({ text: "x".repeat(4096), tail: "new" });
  assert.equal(first.length, final.length);
  const { result } = await runProvider(t, "openai-responses", [first], [final]);
  assert.deepEqual(result.content[0].arguments, JSON.parse(final));
});
