import { createTodoMcpHandler } from "./mcp.ts";
import { createTodoService } from "./service.ts";

const hostname = process.env.GLANCE_SHARED_TODO_HOST ?? "127.0.0.1";
const port = Number(process.env.GLANCE_SHARED_TODO_PORT ?? "8091");
const mcpHostname = process.env.GLANCE_SHARED_TODO_MCP_HOST ?? "127.0.0.1";
const mcpPort = Number(process.env.GLANCE_SHARED_TODO_MCP_PORT ?? "8092");
const databasePath =
  process.env.GLANCE_SHARED_TODO_DATABASE ?? "/var/lib/glance-shared-todo/todo.sqlite";
const allowedOrigin =
  process.env.GLANCE_SHARED_TODO_ALLOWED_ORIGIN ??
  "https://glance.corvus-corax.synology.me";

if (!Number.isInteger(port) || port < 1 || port > 65535) {
  throw new Error("GLANCE_SHARED_TODO_PORT must be a valid TCP port");
}
if (!Number.isInteger(mcpPort) || mcpPort < 1 || mcpPort > 65535) {
  throw new Error("GLANCE_SHARED_TODO_MCP_PORT must be a valid TCP port");
}
if (hostname === mcpHostname && port === mcpPort) {
  throw new Error("The shared todo API and MCP listeners must use different addresses or ports");
}

const todo = createTodoService({ databasePath, allowedOrigin });
const apiServer = Bun.serve({
  hostname,
  port,
  fetch: todo.handle,
});
const mcp = createTodoMcpHandler({ todo, mutationOrigin: allowedOrigin });
const mcpServer = Bun.serve({
  hostname: mcpHostname,
  port: mcpPort,
  fetch: mcp.handle,
});

function shutdown(): void {
  apiServer.stop(true);
  mcpServer.stop(true);
  todo.close();
}

process.on("SIGINT", shutdown);
process.on("SIGTERM", shutdown);

console.log(`glance-shared-todo API listening on ${apiServer.url}`);
console.log(`glance-shared-todo MCP listening on ${mcpServer.url}mcp`);
