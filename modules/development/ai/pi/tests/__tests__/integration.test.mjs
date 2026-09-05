import assert from "node:assert/strict";
import test from "node:test";
import { withWebSocket } from "../websocket-fixture.mjs";
import { join } from "node:path";
import { pathToFileURL } from "node:url";
const root = process.env.PI_NATIVE_TEST_ROOT;
if (!root) throw new Error("Set PI_NATIVE_TEST_ROOT to the patched Pi package");
const load = (path) => import(pathToFileURL(join(root, path)));
const { Agent } = await load(
  "node_modules/@earendil-works/pi-agent-core/dist/agent.js",
);
const { createOpenAICodexExchange, convertResponsesMessages } = await load(
  "node_modules/@earendil-works/pi-ai/dist/index.js",
);
const { SessionManager } = await load("dist/core/session-manager.js");
const { OPENAI_CHECKPOINT_TYPE } = await load(
  "dist/core/openai-capabilities.js",
);
const model = {
  id: "gpt-6-astra-fast",
  name: "Astra",
  api: "openai-codex-responses",
  provider: "openai-codex",
  baseUrl: "https://synthetic.invalid/backend-api",
  reasoning: false,
  input: ["text"],
  cost: { input: 0, output: 0, cacheRead: 0, cacheWrite: 0 },
  contextWindow: 1000,
  maxTokens: 1000,
};
const token = `a.${Buffer.from(JSON.stringify({ "https://api.openai.com/auth": { chatgpt_account_id: "synthetic" } })).toString("base64")}.c`;
const call = {
  type: "function_call",
  id: "fc_1",
  call_id: "call_1",
  name: "lookup",
  arguments: "{}",
  async: true,
};

for (const mode of [
  "complete",
  "origin-failed",
  "output-send-failed",
  "steer",
]) {
  test(
    `real transport, core and persisted replay: ${mode}`,
    { timeout: 3000 },
    async () => {
      let socket,
        executions = 0,
        steeringSent = false;
      class Socket extends EventTarget {
        constructor() {
          super();
          socket = this;
          this.readyState = 0;
          this.sent = [];
          queueMicrotask(() => {
            this.readyState = 1;
            this.dispatchEvent(new Event("open"));
          });
        }
        event(event) {
          this.dispatchEvent(
            new MessageEvent("message", { data: JSON.stringify(event) }),
          );
        }
        terminal(id = "r1") {
          this.event({
            type: "response.completed",
            response: { id, status: "completed", output: [] },
          });
        }
        send(value) {
          const request = JSON.parse(value);
          this.sent.push(request);
          if (request.type === "response.steer") {
            steeringSent = true;
            this.event({
              type: "response.steer.accepted",
              previous_response_id: "r1",
            });
            this.terminal();
            this.event({
              type: "response.created",
              response: { id: "r2", previous_response_id: "r1" },
            });
            this.terminal("r2");
          } else if (!request.previous_response_id) {
            this.event({ type: "response.created", response: { id: "r1" } });
            this.event({
              type: "response.output_item.done",
              output_index: 0,
              item: call,
            });
            // Terminal deliberately withheld until the actual tool has executed.
          } else {
            if (mode === "output-send-failed")
              throw new Error("synthetic output send failed");
            const id = mode === "steer" ? "r3" : "r2";
            this.event({ type: "response.created", response: { id } });
            this.event({
              type: "response.output_item.done",
              output_index: 0,
              item: {
                type: "message",
                id: "msg_final",
                role: "assistant",
                content: [{ type: "output_text", text: "finished" }],
              },
            });
            this.terminal(id);
          }
        }
        close() {
          this.readyState = 3;
          this.dispatchEvent(new Event("close"));
        }
      }
      await withWebSocket(Socket, async () => {
        const sm = SessionManager.inMemory(root);
        const agent = new Agent({
          initialState: {
            model,
            tools: [
              {
                name: "lookup",
                label: "lookup",
                description: "lookup",
                parameters: { type: "object", properties: {} },
                async execute() {
                  executions++;
                  if (mode === "steer")
                    agent.steer({
                      role: "user",
                      content: "new direction",
                      timestamp: Date.now(),
                    });
                  else if (mode === "origin-failed")
                    socket.event({
                      type: "response.failed",
                      response: {
                        id: "r1",
                        error: { message: "synthetic origin failure" },
                      },
                    });
                  else socket.terminal();
                  return {
                    content: [
                      { type: "text", text: "actual side effect outcome" },
                    ],
                    details: {},
                  };
                },
              },
            ],
          },
          streamFn() {
            throw new Error("ordinary stream must not run");
          },
          openAICapabilities: { asyncTools: true, steering: true },
          openAIExchange: (model, context, options) =>
            createOpenAICodexExchange(model, context, {
              ...options,
              apiKey: token,
              onPayload: (body) => ({
                ...body,
                model: "gpt-6-astra",
                service_tier: "priority",
              }),
            }),
        });
        agent.subscribe((event) => {
          if (event.type === "openai_checkpoint")
            sm.appendCustomEntry(OPENAI_CHECKPOINT_TYPE, event.record);
          if (event.type === "message_end") sm.appendMessage(event.message);
        });
        await agent.prompt("go");
        assert.equal(executions, 1);
        assert.equal(socket.readyState, 3);
        assert.equal(socket.sent[0].service_tier, "priority");
        assert.equal(socket.sent[0].model, "gpt-6-astra");
        const messages = sm.buildSessionContext().messages;
        assert.equal(
          messages.filter((message) => message.role === "toolResult").length,
          1,
        );
        assert.equal(
          messages.find((message) => message.role === "toolResult").content[0]
            .text,
          "actual side effect outcome",
        );
        assert.equal(
          messages
            .filter((message) => message.role === "assistant")
            .flatMap((message) => message.content)
            .filter((block) => block.type === "toolCall").length,
          1,
        );
        const wire = convertResponsesMessages(
          model,
          { messages },
          new Set([model.provider]),
        );
        assert.equal(
          JSON.stringify(wire).includes("actual side effect outcome"),
          true,
        );
        if (mode === "steer") {
          assert.equal(steeringSent, true);
          assert.equal(
            messages.filter(
              (message) =>
                message.role === "user" &&
                message.openAI?.deliveryStatus === "incorporated",
            ).length,
            1,
          );
          assert.equal(
            socket.sent.filter(
              (request) =>
                request.type === "response.create" &&
                request.previous_response_id,
            ).length,
            1,
          );
        }
        if (mode === "complete" || mode === "steer")
          assert.equal(agent.state.errorMessage, undefined);
        else assert.match(agent.state.errorMessage, /synthetic/);
      });
    },
  );
}
