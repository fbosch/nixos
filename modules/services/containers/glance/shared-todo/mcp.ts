import type { TodoState } from "./service.ts";

const MCP_PATH = "/mcp";
const MCP_PROTOCOL_VERSION = "2025-06-18";
const MAX_REQUEST_BYTES = 64 * 1024;

type JsonObject = Record<string, unknown>;

type TodoService = {
  getState(): TodoState;
  handle(request: Request): Promise<Response>;
};

class ToolInputError extends Error {}

function isObject(value: unknown): value is JsonObject {
  return typeof value === "object" && value !== null && !Array.isArray(value);
}

function jsonRpcResult(id: unknown, result: unknown): JsonObject {
  return { jsonrpc: "2.0", id, result };
}

function jsonRpcError(id: unknown, code: number, message: string): JsonObject {
  return { jsonrpc: "2.0", id, error: { code, message } };
}

function jsonResponse(body: unknown, status = 200): Response {
  return Response.json(body, {
    status,
    headers: { "Cache-Control": "no-store" },
  });
}

async function readBoundedBody(request: Request): Promise<string | null> {
  const reader = request.body?.getReader();
  if (!reader) return "";

  const decoder = new TextDecoder();
  let bytesRead = 0;
  let body = "";
  while (true) {
    const { done, value } = await reader.read();
    if (done) return body + decoder.decode();

    bytesRead += value.byteLength;
    if (bytesRead > MAX_REQUEST_BYTES) {
      await reader.cancel();
      return null;
    }
    body += decoder.decode(value, { stream: true });
  }
}

function textResult(value: unknown, isError = false): JsonObject {
  return {
    content: [{ type: "text", text: JSON.stringify(value) }],
    structuredContent: value,
    ...(isError ? { isError: true } : {}),
  };
}

function argumentsFrom(params: unknown): JsonObject {
  if (!isObject(params)) {
    throw new ToolInputError("Tool arguments must be an object");
  }
  if (params.arguments === undefined) return {};
  if (!isObject(params.arguments)) throw new ToolInputError("Tool arguments must be an object");

  return params.arguments;
}

function assertKeys(arguments_: JsonObject, allowed: string[]): void {
  const unsupported = Object.keys(arguments_).find((key) => !allowed.includes(key));
  if (unsupported) {
    throw new ToolInputError(`Unsupported argument: ${unsupported}`);
  }
}

function revisionFrom(arguments_: JsonObject): number {
  if (!Number.isSafeInteger(arguments_.revision) || (arguments_.revision as number) < 0) {
    throw new ToolInputError("revision must be a non-negative integer");
  }

  return arguments_.revision as number;
}

function stringFrom(arguments_: JsonObject, name: string): string {
  const value = arguments_[name];
  if (typeof value !== "string" || value.length === 0) {
    throw new ToolInputError(`${name} must be a non-empty string`);
  }

  return value;
}

const tools = [
  {
    name: "list_tasks",
    description: "Return the current revision and ordered shared todo list.",
    inputSchema: { type: "object", additionalProperties: false },
    annotations: { readOnlyHint: true, openWorldHint: false },
  },
  {
    name: "create_task",
    description: "Create a task at the end of the shared todo list. Call list_tasks first and pass its revision.",
    inputSchema: {
      type: "object",
      properties: {
        text: { type: "string", minLength: 1, maxLength: 500 },
        revision: { type: "integer", minimum: 0 },
      },
      required: ["text", "revision"],
      additionalProperties: false,
    },
    annotations: { destructiveHint: false, openWorldHint: false },
  },
  {
    name: "update_task",
    description: "Update a task's text or completion state. Call list_tasks first and pass its revision.",
    inputSchema: {
      type: "object",
      properties: {
        id: { type: "string", minLength: 1 },
        text: { type: "string", minLength: 1, maxLength: 500 },
        checked: { type: "boolean" },
        revision: { type: "integer", minimum: 0 },
      },
      required: ["id", "revision"],
      anyOf: [{ required: ["text"] }, { required: ["checked"] }],
      additionalProperties: false,
    },
    annotations: { destructiveHint: false, idempotentHint: true, openWorldHint: false },
  },
  {
    name: "delete_task",
    description: "Delete a task from the shared todo list. Call list_tasks first and pass its revision.",
    inputSchema: {
      type: "object",
      properties: {
        id: { type: "string", minLength: 1 },
        revision: { type: "integer", minimum: 0 },
      },
      required: ["id", "revision"],
      additionalProperties: false,
    },
    annotations: { destructiveHint: true, openWorldHint: false },
  },
  {
    name: "reorder_tasks",
    description: "Set the complete ordering of current task IDs. Call list_tasks first and pass its revision.",
    inputSchema: {
      type: "object",
      properties: {
        taskIds: {
          type: "array",
          items: { type: "string", minLength: 1 },
        },
        revision: { type: "integer", minimum: 0 },
      },
      required: ["taskIds", "revision"],
      additionalProperties: false,
    },
    annotations: { destructiveHint: false, idempotentHint: true, openWorldHint: false },
  },
];

export function createTodoMcpHandler(options: {
  todo: TodoService;
  mutationOrigin: string;
}) {
  async function mutate(method: string, path: string, body: JsonObject): Promise<JsonObject> {
    const response = await options.todo.handle(
      new Request(`http://localhost${path}`, {
        method,
        headers: {
          "Content-Type": "application/json",
          Origin: options.mutationOrigin,
        },
        body: JSON.stringify(body),
      }),
    );
    const result = await response.json();
    return textResult(result, !response.ok);
  }

  async function callTool(params: unknown): Promise<JsonObject> {
    if (!isObject(params) || typeof params.name !== "string") {
      throw new ToolInputError("Tool name must be a string");
    }

    if (params.name === "list_tasks") {
      const arguments_ = argumentsFrom(params);
      assertKeys(arguments_, []);
      return textResult(options.todo.getState());
    }

    if (params.name === "create_task") {
      const arguments_ = argumentsFrom(params);
      assertKeys(arguments_, ["text", "revision"]);
      return mutate("POST", "/api/shared-todo/tasks", {
        text: stringFrom(arguments_, "text"),
        revision: revisionFrom(arguments_),
      });
    }

    if (params.name === "update_task") {
      const arguments_ = argumentsFrom(params);
      assertKeys(arguments_, ["id", "text", "checked", "revision"]);
      if (arguments_.text === undefined && arguments_.checked === undefined) {
        throw new ToolInputError("Provide text or checked");
      }
      if (arguments_.text !== undefined && typeof arguments_.text !== "string") {
        throw new ToolInputError("text must be a string");
      }
      if (arguments_.checked !== undefined && typeof arguments_.checked !== "boolean") {
        throw new ToolInputError("checked must be a boolean");
      }

      return mutate(
        "PATCH",
        `/api/shared-todo/tasks/${encodeURIComponent(stringFrom(arguments_, "id"))}`,
        {
          ...(arguments_.text === undefined ? {} : { text: arguments_.text }),
          ...(arguments_.checked === undefined ? {} : { checked: arguments_.checked }),
          revision: revisionFrom(arguments_),
        },
      );
    }

    if (params.name === "delete_task") {
      const arguments_ = argumentsFrom(params);
      assertKeys(arguments_, ["id", "revision"]);
      return mutate(
        "DELETE",
        `/api/shared-todo/tasks/${encodeURIComponent(stringFrom(arguments_, "id"))}`,
        { revision: revisionFrom(arguments_) },
      );
    }

    if (params.name === "reorder_tasks") {
      const arguments_ = argumentsFrom(params);
      assertKeys(arguments_, ["taskIds", "revision"]);
      if (
        !Array.isArray(arguments_.taskIds) ||
        arguments_.taskIds.some((id) => typeof id !== "string" || id.length === 0)
      ) {
        throw new ToolInputError("taskIds must be an array of non-empty strings");
      }

      return mutate("PUT", "/api/shared-todo/tasks/order", {
        taskIds: arguments_.taskIds,
        revision: revisionFrom(arguments_),
      });
    }

    throw new ToolInputError(`Unknown tool: ${params.name}`);
  }

  async function dispatch(message: JsonObject): Promise<JsonObject | undefined> {
    const hasId = Object.hasOwn(message, "id");
    if (typeof message.method !== "string" || message.jsonrpc !== "2.0") {
      return hasId ? jsonRpcError(message.id, -32600, "Invalid Request") : undefined;
    }

    if (!hasId) return undefined;

    if (message.method === "initialize") {
      return jsonRpcResult(message.id, {
        protocolVersion: MCP_PROTOCOL_VERSION,
        capabilities: { tools: {} },
        serverInfo: { name: "glance-shared-todo", version: "1.0.0" },
        instructions: "List tasks before mutating them and pass the returned revision. On a conflict, list tasks again before retrying.",
      });
    }
    if (message.method === "ping") return jsonRpcResult(message.id, {});
    if (message.method === "tools/list") return jsonRpcResult(message.id, { tools });
    if (message.method !== "tools/call") {
      return jsonRpcError(message.id, -32601, "Method not found");
    }

    try {
      return jsonRpcResult(message.id, await callTool(message.params));
    } catch (error) {
      if (error instanceof ToolInputError) {
        return jsonRpcResult(
          message.id,
          textResult({ error: { code: "invalid_request", message: error.message } }, true),
        );
      }
      throw error;
    }
  }

  async function handle(request: Request): Promise<Response> {
    const url = new URL(request.url);
    if (url.pathname !== MCP_PATH) return jsonResponse({ error: "Not found" }, 404);
    if (request.headers.has("Origin")) {
      return jsonResponse({ error: "Browser origins are not allowed" }, 403);
    }
    if (request.method !== "POST") {
      return new Response(null, { status: 405, headers: { Allow: "POST" } });
    }
    if (request.headers.get("Content-Type")?.split(";", 1)[0] !== "application/json") {
      return jsonResponse({ error: "Content-Type must be application/json" }, 415);
    }

    const contentLength = Number(request.headers.get("Content-Length") ?? 0);
    if (contentLength > MAX_REQUEST_BYTES) {
      return jsonResponse({ error: "Request body is too large" }, 413);
    }

    const raw = await readBoundedBody(request);
    if (raw === null) {
      return jsonResponse({ error: "Request body is too large" }, 413);
    }

    let message: unknown;
    try {
      message = JSON.parse(raw);
    } catch {
      return jsonResponse(jsonRpcError(null, -32700, "Parse error"), 400);
    }
    if (!isObject(message)) {
      return jsonResponse(jsonRpcError(null, -32600, "Invalid Request"), 400);
    }

    const protocolVersion = request.headers.get("MCP-Protocol-Version");
    if (
      message.method !== "initialize" &&
      protocolVersion !== null &&
      protocolVersion !== MCP_PROTOCOL_VERSION
    ) {
      return jsonResponse(
        jsonRpcError(message.id ?? null, -32600, "Unsupported MCP protocol version"),
        400,
      );
    }

    try {
      const response = await dispatch(message);
      return response ? jsonResponse(response) : new Response(null, { status: 202 });
    } catch {
      return jsonResponse(jsonRpcError(message.id ?? null, -32603, "Internal error"), 500);
    }
  }

  return { handle };
}
