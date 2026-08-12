import { createTodoService } from "./service.ts";

const hostname = process.env.GLANCE_SHARED_TODO_HOST ?? "127.0.0.1";
const port = Number(process.env.GLANCE_SHARED_TODO_PORT ?? "8091");
const databasePath =
  process.env.GLANCE_SHARED_TODO_DATABASE ?? "/var/lib/glance-shared-todo/todo.sqlite";
const allowedOrigin =
  process.env.GLANCE_SHARED_TODO_ALLOWED_ORIGIN ??
  "https://glance.corvus-corax.synology.me";

if (!Number.isInteger(port) || port < 1 || port > 65535) {
  throw new Error("GLANCE_SHARED_TODO_PORT must be a valid TCP port");
}

const todo = createTodoService({ databasePath, allowedOrigin });
const server = Bun.serve({
  hostname,
  port,
  fetch: todo.handle,
});

function shutdown(): void {
  server.stop(true);
  todo.close();
}

process.on("SIGINT", shutdown);
process.on("SIGTERM", shutdown);

console.log(`glance-shared-todo listening on ${server.url}`);
