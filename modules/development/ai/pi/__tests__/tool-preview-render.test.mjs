import assert from "node:assert/strict";
import { join } from "node:path";
import { test } from "node:test";
import { pathToFileURL } from "node:url";

const packageRoot = process.env.PI_TEST_PACKAGE;
assert.ok(packageRoot, "PI_TEST_PACKAGE must point to the installed Pi package");
const load = (root, path) => import(pathToFileURL(join(root, "dist", path)).href);
const { Container, Text } = await load(join(packageRoot, "../pi-tui"), "index.js");
const { ToolExecutionComponent } = await load(packageRoot, "modes/interactive/components/tool-execution.js");
const { AssistantMessageComponent } = await load(packageRoot, "modes/interactive/components/assistant-message.js");
const { InteractiveMode } = await load(packageRoot, "modes/interactive/interactive-mode.js");
const { initTheme } = await load(packageRoot, "modes/interactive/theme/theme.js");
const { parseToolCallArguments } = await load(join(packageRoot, "../pi-ai"), "utils/json-parse.js");
const { ToolCallArgumentsStream } = await load(join(packageRoot, "../pi-ai"), "utils/streaming-json.js");
initTheme("dark");

function renderer(observe = () => {}) {
  return {
    renderCall(args, _theme, context) {
      observe(context);
      return new Text(JSON.stringify({ args, started: context.executionStarted, complete: context.argsComplete, expanded: context.expanded }), 0, 0);
    },
    renderResult(result, options) {
      return new Text(JSON.stringify({ result, options }), 0, 0);
    },
  };
}

function fixture(content, definition = renderer()) {
  let frames = 0;
  const ui = { requestRender: () => { frames++; } };
  const host = {
    isInitialized: true,
    footer: { invalidate() {} },
    programStatus: { handleEvent() {} },
    streamingComponent: new AssistantMessageComponent(),
    streamingMessage: undefined,
    pendingTools: new Map(),
    chatContainer: new Container(),
    settingsManager: { getShowImages: () => false, getImageWidthCells: () => 60 },
    outputPad: 1,
    toolOutputExpanded: false,
    ui,
    sessionManager: { getCwd: () => process.cwd() },
    getRegisteredToolDefinition: () => definition,
  };
  host.chatContainer.addChild(host.streamingComponent);
  const message = {
    role: "assistant", content, api: "openai-completions", provider: "fixture", model: "fixture",
    usage: { input: 0, output: 0, cacheRead: 0, cacheWrite: 0, totalTokens: 0, cost: { input: 0, output: 0, cacheRead: 0, cacheWrite: 0, total: 0 } },
    stopReason: "toolUse", timestamp: 0,
  };
  return {
    host, message, frames: () => frames,
    update: (type = "toolcall_delta", contentIndex = 0, delta = "") => InteractiveMode.prototype.handleEvent.call(host, {
      type: "message_update", message: { ...message },
      assistantMessageEvent: { type, contentIndex, delta, partial: message },
    }),
  };
}

function call(id, args = {}) {
  return { type: "toolCall", id, name: "replace", arguments: args };
}

test("unchanged arguments reuse the tool preview, while new argument objects rebuild it", () => {
  let rendered = 0;
  const args = { path: "æøå.txt", text: 'quote " and \\ slash\n😀' };
  const component = new ToolExecutionComponent("replace", "call", args, {}, renderer(() => rendered++), { requestRender() {} }, process.cwd());
  const before = component.render(100);
  const initial = rendered;
  assert.equal(component.updateArgs(args), false);
  assert.equal(rendered, initial);
  assert.deepEqual(component.render(100), before);
  assert.equal(component.updateArgs({ ...args }), true);
  assert.deepEqual(component.render(100), before);
  assert.equal(rendered, initial + 1);
  assert.equal(component.updateArgs({ ...args, text: "changed æøå" }), true);
  assert.ok(component.render(100).join("\n").includes("changed æøå"));
});

test("execution, final arguments, results, expansion and invalidation still refresh unchanged arguments", () => {
  let rendered = 0;
  const args = { text: "æøå" };
  const component = new ToolExecutionComponent("replace", "call", args, {}, renderer(() => rendered++), { requestRender() {} }, process.cwd());
  for (const action of [
    () => component.markExecutionStarted(),
    () => component.setArgsComplete(),
    () => component.updateResult({ content: [{ type: "text", text: "partial" }], isError: false }, true),
    () => component.updateResult({ content: [{ type: "text", text: "done æøå" }], isError: false, durationMs: 2 }),
    () => component.setExpanded(true),
    () => component.invalidate(),
  ]) {
    const before = rendered;
    action();
    assert.ok(rendered > before);
    assert.equal(component.updateArgs(args), false);
  }
  const screen = component.render(200).join("\n");
  assert.ok(screen.includes('"started":true'));
  assert.ok(screen.includes('"complete":true'));
  assert.ok(screen.includes('"expanded":true'));
  assert.ok(screen.includes("done æøå"));
});

test("only unchanged tool-call deltas skip frames, and every changed call is checked", async () => {
  const first = call("first", { path: "a.txt" });
  const second = call("second", { path: "b.txt" });
  const f = fixture([first, second]);
  await f.update();
  assert.equal(f.frames(), 1, "new tools are drawn");
  await f.update();
  assert.equal(f.frames(), 1, "unchanged tools do not schedule a frame");
  first.arguments = { ...first.arguments, text: "first changes during the second call's delta" };
  await f.update("toolcall_delta", 1);
  assert.equal(f.frames(), 2);
  assert.ok(f.host.chatContainer.render(100).join("\n").includes("first changes"));
  for (const type of ["text_delta", "thinking_delta", "toolcall_start", "toolcall_end"]) {
    const before = f.frames();
    await f.update(type);
    assert.equal(f.frames(), before + 1, `${type} still schedules a frame`);
  }
  second.arguments = { ...second.arguments, text: "second changes" };
  await f.update("toolcall_delta", 1);
  assert.equal(f.frames(), 7);
});

for (const chunkSize of [1, 16, 128]) {
  test(`streamed previews match a fresh rendering with ${chunkSize}-character chunks`, async () => {
    const expected = { path: "æøå.txt", text: ('line "quoted" \\ café 😀\n\t' + "x".repeat(100)).repeat(32), tail: true };
    const json = JSON.stringify(expected);
    const block = call("stream");
    const f = fixture([block]);
    await f.update("toolcall_start");
    let drawn = f.host.chatContainer.render(80);
    let parsed = 0;
    const argumentsStream = new ToolCallArgumentsStream();
    for (let end = chunkSize; end < json.length + chunkSize; end += chunkSize) {
      const before = block.arguments;
      block.arguments = argumentsStream.append(json.slice(end - chunkSize, end));
      const frames = f.frames();
      await f.update();
      assert.equal(f.frames() > frames, before !== block.arguments, "only changed argument snapshots request frames");
      const lines = f.host.chatContainer.render(80);
      if (before === block.arguments) assert.deepEqual(lines, drawn, "skipped frames would have drawn the same lines");
      if (before !== block.arguments) {
        parsed++;
        const fresh = fixture([call("stream", block.arguments)]);
        await fresh.update("toolcall_start");
        assert.deepEqual(lines, fresh.host.chatContainer.render(80));
      }
      drawn = lines;
    }
    assert.ok(parsed > 0 && parsed < json.length / chunkSize);
    block.arguments = parseToolCallArguments(json).arguments;
    await f.update("toolcall_end");
    assert.deepEqual(block.arguments, expected);
    assert.deepEqual(f.host.pendingTools.get("stream").args, expected);
  });
}
