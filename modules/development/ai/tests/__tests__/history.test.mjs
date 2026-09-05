import assert from "node:assert/strict";
import test from "node:test";
import { join } from "node:path";
import { pathToFileURL } from "node:url";

const root =
  process.env.PI_NATIVE_TEST_ROOT ??
  new URL("../../", import.meta.url).pathname;
const { transformMessages } = await import(
  pathToFileURL(
    join(
      root,
      "node_modules/@earendil-works/pi-ai/dist/api/transform-messages.js",
    ),
  )
);
const {
  convertResponsesMessages,
  processResponsesStream,
  AssistantMessageEventStream,
} = await import(
  pathToFileURL(join(root, "node_modules/@earendil-works/pi-ai/dist/index.js"))
);
const model = {
  id: "astra",
  provider: "openai-codex",
  api: "openai-codex-responses",
  input: ["text", "image"],
  cost: { input: 0, output: 0, cacheRead: 0, cacheWrite: 0 },
};
const metadata = { version: 1, exchangeId: "exchange-1", responseId: "r1" };
const usage = {
  input: 0,
  output: 0,
  cacheRead: 0,
  cacheWrite: 0,
  totalTokens: 0,
  cost: { input: 0, output: 0, cacheRead: 0, cacheWrite: 0, total: 0 },
};
function fixture() {
  return [
    {
      role: "assistant",
      model: model.id,
      provider: model.provider,
      api: model.api,
      content: [
        {
          type: "toolCall",
          name: "lookup",
          id: "call1|fc_1",
          arguments: { city: "Århus" },
          async: true,
        },
      ],
      stopReason: "toolUse",
      timestamp: 1,
      usage,
      openAI: metadata,
    },
    {
      role: "user",
      content: "change direction",
      timestamp: 2,
      openAI: { ...metadata, deliveryId: "d1", deliveryStatus: "incorporated" },
    },
    {
      role: "toolResult",
      toolName: "lookup",
      toolCallId: "call1|fc_1",
      content: [
        { type: "text", text: "actual result" },
        { type: "image", data: "image-data", mimeType: "image/png" },
      ],
      timestamp: 3,
      isError: false,
      openAI: metadata,
    },
  ];
}

test("same-model native history retains late actual results without synthetic duplicates", () => {
  const messages = fixture();
  const transformed = transformMessages(messages, model);
  assert.deepEqual(
    transformed.map((message) => message.role),
    ["assistant", "user", "toolResult"],
  );
  assert.equal(transformed[2].content[0].text, "actual result");
  const wire = convertResponsesMessages(
    model,
    { messages },
    new Set([model.provider]),
  );
  assert.equal(wire.find((item) => item.type === "function_call").async, true);
  assert.equal(
    wire.filter((item) => item.type === "function_call_output").length,
    1,
  );
  assert.equal(
    wire.find((item) => item.type === "function_call_output").call_id,
    "call1",
  );
});

test("cross-provider native history preserves chronological calls, actual outputs, and images", () => {
  const messages = fixture();
  const transformed = transformMessages(messages, {
    ...model,
    id: "other",
    provider: "anthropic",
    api: "anthropic-messages",
  });
  assert.equal(
    transformed[0].content.some((block) => block.type === "toolCall"),
    false,
  );
  assert.match(transformed[0].content[0].text, /Århus/);
  assert.equal(transformed[1].content, "change direction");
  assert.match(transformed[2].content[0].text, /untrusted data/);
  assert.match(transformed[2].content[0].text, /actual result/);
  assert.equal(transformed[2].content[1].type, "image");
  assert.equal(messages[0].content[0].type, "toolCall");
});

test("failed native responses never discard recorded tool effects during replay", () => {
  const messages = fixture();
  messages[0].stopReason = "aborted";
  const transformed = transformMessages(messages, model);
  assert.equal(transformed.length, 3);
  assert.match(transformed[0].content.at(-1).text, /outcomes remain valid/);
  assert.match(transformed[2].content[0].text, /actual result/);
  assert.equal(transformed[0].stopReason, "stop");
});

test("ordinary orphan repair remains unchanged", () => {
  const [assistant, user] = fixture();
  delete assistant.openAI;
  delete assistant.content[0].async;
  const transformed = transformMessages([assistant, user], model);
  assert.deepEqual(
    transformed.map((message) => message.role),
    ["assistant", "toolResult", "user"],
  );
  assert.equal(transformed[1].content[0].text, "No result provided");
});

test("only native parser mode accepts a steered interruption and retains complete async calls", async () => {
  for (const native of [false, true]) {
    const output = {
      role: "assistant",
      model: model.id,
      provider: model.provider,
      api: model.api,
      content: [],
      usage: structuredClone(usage),
      stopReason: "pending",
      timestamp: 1,
    };
    const stream = new AssistantMessageEventStream();
    const item = {
      type: "function_call",
      id: "fc_1",
      call_id: "call1",
      name: "lookup",
      arguments: "{}",
      async: true,
    };
    async function* events() {
      yield { type: "response.created", response: { id: "r1" } };
      yield { type: "response.output_item.done", output_index: 0, item };
      yield {
        type: "response.incomplete",
        response: {
          id: "r1",
          status: "incomplete",
          incomplete_details: { reason: "steered" },
          output: [item],
        },
      };
    }
    await processResponsesStream(events(), output, stream, model, {
      allowSteeringInterruption: native,
    });
    assert.equal(output.stopReason, native ? "toolUse" : "error");
    assert.equal(output.content[0].async, true);
    assert.equal(output.rawStopReason, "incomplete.steered");
  }
});
