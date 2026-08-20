import { afterEach, describe, expect, test } from "bun:test";
import { createTodoMcpHandler } from "../mcp.ts";
import { createTodoService, type TodoState } from "../service.ts";

const ORIGIN = "https://glance.corvus-corax.synology.me";
const services: ReturnType<typeof createTodoService>[] = [];

afterEach(() => {
  for (const service of services.splice(0)) service.close();
});

function handler() {
  const todo = createTodoService({ databasePath: ":memory:", allowedOrigin: ORIGIN });
  services.push(todo);
  return createTodoMcpHandler({ todo, mutationOrigin: ORIGIN });
}

async function rpc(
  mcp: ReturnType<typeof handler>,
  id: number,
  method: string,
  params?: unknown,
  protocolVersion?: string,
) {
  const response = await mcp.handle(
    new Request("http://localhost/mcp", {
      method: "POST",
      headers: {
        Accept: "application/json, text/event-stream",
        "Content-Type": "application/json",
        ...(protocolVersion ? { "MCP-Protocol-Version": protocolVersion } : {}),
      },
      body: JSON.stringify({ jsonrpc: "2.0", id, method, params }),
    }),
  );
  return response.json();
}

function state(response: { result: { structuredContent: TodoState } }) {
  return response.result.structuredContent;
}

describe("shared todo MCP", () => {
  test("initializes and advertises the todo tools", async () => {
    const mcp = handler();
    const initialized = await rpc(mcp, 1, "initialize", {
      protocolVersion: "2025-11-25",
      capabilities: {},
      clientInfo: { name: "test", version: "1.0.0" },
    });
    expect(initialized.result).toMatchObject({
      protocolVersion: "2025-06-18",
      serverInfo: { name: "glance-shared-todo" },
    });

    const notification = await mcp.handle(
      new Request("http://localhost/mcp", {
        method: "POST",
        headers: {
          "Content-Type": "application/json",
          "MCP-Protocol-Version": "2025-06-18",
        },
        body: JSON.stringify({ jsonrpc: "2.0", method: "notifications/initialized" }),
      }),
    );
    expect(notification.status).toBe(202);

    const listed = await rpc(mcp, 2, "tools/list", undefined, "2025-06-18");
    expect(listed.result.tools.map((tool: { name: string }) => tool.name)).toEqual([
      "list_tasks",
      "create_task",
      "update_task",
      "delete_task",
      "reorder_tasks",
    ]);

    const stream = await mcp.handle(
      new Request("http://localhost/mcp", {
        headers: { Accept: "text/event-stream" },
      }),
    );
    expect(stream.status).toBe(405);

    const unsupportedResponse = await mcp.handle(
      new Request("http://localhost/mcp", {
        method: "POST",
        headers: {
          "Content-Type": "application/json",
          "MCP-Protocol-Version": "2099-01-01",
        },
        body: JSON.stringify({ jsonrpc: "2.0", id: 3, method: "tools/list" }),
      }),
    );
    expect(unsupportedResponse.status).toBe(400);
    expect(await unsupportedResponse.json()).toMatchObject({
      error: { message: "Unsupported MCP protocol version" },
    });
  });

  test("creates, updates, reorders, and deletes tasks", async () => {
    const mcp = handler();
    let response = await rpc(mcp, 1, "tools/call", {
      name: "create_task",
      arguments: { text: "First", revision: 0 },
    });
    expect(state(response)).toMatchObject({
      revision: 1,
      tasks: [{ text: "First", checked: false }],
    });

    response = await rpc(mcp, 2, "tools/call", {
      name: "create_task",
      arguments: { text: "Second", revision: 1 },
    });
    const [first, second] = state(response).tasks;

    response = await rpc(mcp, 3, "tools/call", {
      name: "update_task",
      arguments: { id: first.id, checked: true, revision: 2 },
    });
    expect(state(response)).toMatchObject({
      revision: 3,
      tasks: [{ id: first.id, checked: true }, { id: second.id }],
    });

    response = await rpc(mcp, 4, "tools/call", {
      name: "reorder_tasks",
      arguments: { taskIds: [second.id, first.id], revision: 3 },
    });
    expect(state(response).tasks.map((task: { id: string }) => task.id)).toEqual([
      second.id,
      first.id,
    ]);

    response = await rpc(mcp, 5, "tools/call", {
      name: "delete_task",
      arguments: { id: first.id, revision: 4 },
    });
    expect(state(response)).toMatchObject({ revision: 5, tasks: [{ id: second.id }] });
  });

  test("returns tool errors for stale revisions and invalid arguments", async () => {
    const mcp = handler();
    await rpc(mcp, 1, "tools/call", {
      name: "create_task",
      arguments: { text: "Current", revision: 0 },
    });

    const conflict = await rpc(mcp, 2, "tools/call", {
      name: "create_task",
      arguments: { text: "Stale", revision: 0 },
    });
    expect(conflict.result).toMatchObject({
      isError: true,
      structuredContent: { error: { code: "conflict" } },
    });

    const invalid = await rpc(mcp, 3, "tools/call", {
      name: "update_task",
      arguments: { id: "missing", revision: 1 },
    });
    expect(invalid.result).toMatchObject({
      isError: true,
      structuredContent: { error: { code: "invalid_request" } },
    });
  });

  test("allows only one simultaneous mutation for a revision", async () => {
    const mcp = handler();
    const responses = await Promise.all([
      rpc(mcp, 1, "tools/call", {
        name: "create_task",
        arguments: { text: "First", revision: 0 },
      }),
      rpc(mcp, 2, "tools/call", {
        name: "create_task",
        arguments: { text: "Second", revision: 0 },
      }),
    ]);

    expect(
      responses.filter(
        (response) => response.result.structuredContent?.error?.code === "conflict",
      ),
    ).toHaveLength(1);
    expect(responses.filter((response) => response.result.isError !== true)).toHaveLength(1);
    const listed = await rpc(mcp, 3, "tools/call", {
      name: "list_tasks",
      arguments: {},
    });
    expect(state(listed)).toMatchObject({ revision: 1 });
    expect(state(listed).tasks).toHaveLength(1);
  });

  test("rejects browser-origin requests", async () => {
    const mcp = handler();
    const response = await mcp.handle(
      new Request("http://localhost/mcp", {
        method: "POST",
        headers: {
          "Content-Type": "application/json",
          Origin: "https://attacker.example",
        },
        body: JSON.stringify({ jsonrpc: "2.0", id: 1, method: "tools/list" }),
      }),
    );

    expect(response.status).toBe(403);
  });

  test("cancels request bodies that exceed the size limit", async () => {
    const mcp = handler();
    let cancelled = false;
    const body = new ReadableStream<Uint8Array>({
      start(controller) {
        controller.enqueue(new Uint8Array(64 * 1024));
        controller.enqueue(new Uint8Array(1));
      },
      cancel() {
        cancelled = true;
      },
    });
    const response = await mcp.handle(
      new Request("http://localhost/mcp", {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body,
      }),
    );

    expect(response.status).toBe(413);
    expect(cancelled).toBe(true);
  });
});
