import { Database } from "bun:sqlite";

const API_PREFIX = "/api/shared-todo";
const MAX_REQUEST_BYTES = 16 * 1024;
const MAX_TASK_TEXT_LENGTH = 500;

type TaskRow = {
  id: string;
  text: string;
  checked: number;
  position: number;
};

export type Task = {
  id: string;
  text: string;
  checked: boolean;
};

export type TodoState = {
  revision: number;
  tasks: Task[];
};

type ErrorCode =
  | "conflict"
  | "invalid_content_type"
  | "invalid_json"
  | "invalid_origin"
  | "invalid_request"
  | "not_found"
  | "request_too_large";

class ApiError extends Error {
  constructor(
    readonly status: number,
    readonly code: ErrorCode,
    message: string,
  ) {
    super(message);
  }
}

function json(data: unknown, status = 200): Response {
  return Response.json(data, {
    status,
    headers: { "Cache-Control": "no-store" },
  });
}

function errorResponse(error: unknown): Response {
  if (error instanceof ApiError) {
    return json(
      { error: { code: error.code, message: error.message } },
      error.status,
    );
  }

  console.error("glance-shared-todo request failed", error);
  return json(
    { error: { code: "internal_error", message: "Internal server error" } },
    500,
  );
}

function isObject(value: unknown): value is Record<string, unknown> {
  return typeof value === "object" && value !== null && !Array.isArray(value);
}

function parseRevision(value: unknown): number {
  if (!Number.isSafeInteger(value) || (value as number) < 0) {
    throw new ApiError(400, "invalid_request", "revision must be a non-negative integer");
  }

  return value as number;
}

function parseText(value: unknown): string {
  if (typeof value !== "string") {
    throw new ApiError(400, "invalid_request", "text must be a string");
  }

  const text = value.trim();
  if (text.length === 0 || text.length > MAX_TASK_TEXT_LENGTH) {
    throw new ApiError(
      400,
      "invalid_request",
      `text must contain between 1 and ${MAX_TASK_TEXT_LENGTH} characters`,
    );
  }

  return text;
}

async function parseBody(request: Request): Promise<Record<string, unknown>> {
  const contentType = request.headers.get("Content-Type")?.split(";", 1)[0];
  if (contentType !== "application/json") {
    throw new ApiError(415, "invalid_content_type", "Content-Type must be application/json");
  }

  const contentLength = Number(request.headers.get("Content-Length") ?? 0);
  if (contentLength > MAX_REQUEST_BYTES) {
    throw new ApiError(413, "request_too_large", "Request body is too large");
  }

  const raw = await request.text();
  if (new TextEncoder().encode(raw).byteLength > MAX_REQUEST_BYTES) {
    throw new ApiError(413, "request_too_large", "Request body is too large");
  }

  let body: unknown;
  try {
    body = JSON.parse(raw);
  } catch {
    throw new ApiError(400, "invalid_json", "Request body must be valid JSON");
  }

  if (!isObject(body)) {
    throw new ApiError(400, "invalid_request", "Request body must be a JSON object");
  }

  return body;
}

export function createTodoService(options: {
  databasePath: string;
  allowedOrigin: string;
}) {
  const database = new Database(options.databasePath, { create: true });
  const subscribers = new Set<ReadableStreamDefaultController<Uint8Array>>();
  const encoder = new TextEncoder();

  database.exec("PRAGMA journal_mode = WAL");
  database.exec("PRAGMA foreign_keys = ON");
  database.exec(`
    CREATE TABLE IF NOT EXISTS todo_metadata (
      singleton INTEGER PRIMARY KEY CHECK (singleton = 1),
      revision INTEGER NOT NULL
    );
    INSERT OR IGNORE INTO todo_metadata (singleton, revision) VALUES (1, 0);

    CREATE TABLE IF NOT EXISTS todo_tasks (
      id TEXT PRIMARY KEY,
      text TEXT NOT NULL CHECK (length(text) BETWEEN 1 AND ${MAX_TASK_TEXT_LENGTH}),
      checked INTEGER NOT NULL CHECK (checked IN (0, 1)),
      position INTEGER NOT NULL UNIQUE
    );
    CREATE INDEX IF NOT EXISTS todo_tasks_position ON todo_tasks(position);
  `);

  const revisionQuery = database.query<{ revision: number }, []>(
    "SELECT revision FROM todo_metadata WHERE singleton = 1",
  );
  const taskListQuery = database.query<TaskRow, []>(
    "SELECT id, text, checked, position FROM todo_tasks ORDER BY position ASC",
  );

  function getRevision(): number {
    return revisionQuery.get()!.revision;
  }

  function getState(): TodoState {
    return {
      revision: getRevision(),
      tasks: taskListQuery.all().map(({ id, text, checked }) => ({
        id,
        text,
        checked: checked === 1,
      })),
    };
  }

  function assertRevision(expected: number): void {
    if (getRevision() !== expected) {
      throw new ApiError(409, "conflict", "The task list changed; reload and try again");
    }
  }

  function advanceRevision(): number {
    database.run(
      "UPDATE todo_metadata SET revision = revision + 1 WHERE singleton = 1",
    );
    return getRevision();
  }

  function publishRevision(revision: number): void {
    const event = encoder.encode(`event: revision\ndata: ${revision}\n\n`);
    for (const subscriber of subscribers) {
      try {
        subscriber.enqueue(event);
      } catch {
        subscribers.delete(subscriber);
      }
    }
  }

  const createTask = database.transaction((text: string, expectedRevision: number) => {
    assertRevision(expectedRevision);
    const nextPosition = database
      .query<{ position: number }, []>(
        "SELECT COALESCE(MAX(position), -1) + 1 AS position FROM todo_tasks",
      )
      .get()!.position;
    database.run(
      "INSERT INTO todo_tasks (id, text, checked, position) VALUES (?, ?, 0, ?)",
      [crypto.randomUUID(), text, nextPosition],
    );
    return advanceRevision();
  });

  const updateTask = database.transaction(
    (id: string, body: Record<string, unknown>, expectedRevision: number) => {
      assertRevision(expectedRevision);
      const current = database
        .query<TaskRow, [string]>(
          "SELECT id, text, checked, position FROM todo_tasks WHERE id = ?",
        )
        .get(id);
      if (!current) {
        throw new ApiError(404, "not_found", "Task not found");
      }

      const hasText = Object.hasOwn(body, "text");
      const hasChecked = Object.hasOwn(body, "checked");
      if (hasText === false && hasChecked === false) {
        throw new ApiError(400, "invalid_request", "Provide text or checked");
      }
      if (hasChecked && typeof body.checked !== "boolean") {
        throw new ApiError(400, "invalid_request", "checked must be a boolean");
      }

      const text = hasText ? parseText(body.text) : current.text;
      const checked = hasChecked ? (body.checked ? 1 : 0) : current.checked;
      database.run("UPDATE todo_tasks SET text = ?, checked = ? WHERE id = ?", [
        text,
        checked,
        id,
      ]);
      return advanceRevision();
    },
  );

  const deleteTask = database.transaction((id: string, expectedRevision: number) => {
    assertRevision(expectedRevision);
    const result = database.run("DELETE FROM todo_tasks WHERE id = ?", [id]);
    if (result.changes === 0) {
      throw new ApiError(404, "not_found", "Task not found");
    }
    return advanceRevision();
  });

  const reorderTasks = database.transaction(
    (taskIds: string[], expectedRevision: number) => {
      assertRevision(expectedRevision);
      const existingIds = taskListQuery.all().map(({ id }) => id);
      if (
        taskIds.length !== existingIds.length ||
        new Set(taskIds).size !== taskIds.length ||
        taskIds.some((id) => existingIds.includes(id) === false)
      ) {
        throw new ApiError(
          400,
          "invalid_request",
          "taskIds must contain every current task exactly once",
        );
      }

      const temporaryOffset = taskIds.length + 1;
      database.run("UPDATE todo_tasks SET position = position + ?", [temporaryOffset]);
      const updatePosition = database.query(
        "UPDATE todo_tasks SET position = ? WHERE id = ?",
      );
      taskIds.forEach((id, position) => updatePosition.run(position, id));
      return advanceRevision();
    },
  );

  const replaceTasks = database.transaction(
    (tasks: Task[], expectedRevision: number) => {
      assertRevision(expectedRevision);
      if (new Set(tasks.map(({ id }) => id)).size !== tasks.length) {
        throw new ApiError(400, "invalid_request", "Task IDs must be unique");
      }

      database.run("DELETE FROM todo_tasks");
      const insertTask = database.query(
        "INSERT INTO todo_tasks (id, text, checked, position) VALUES (?, ?, ?, ?)",
      );
      tasks.forEach((task, position) => {
        insertTask.run(task.id, task.text, task.checked ? 1 : 0, position);
      });
      return advanceRevision();
    },
  );

  function requireAllowedOrigin(request: Request): void {
    if (request.headers.get("Origin") !== options.allowedOrigin) {
      throw new ApiError(403, "invalid_origin", "Request origin is not allowed");
    }
  }

  function eventStream(): Response {
    let keepalive: ReturnType<typeof setInterval> | undefined;
    let controller: ReadableStreamDefaultController<Uint8Array> | undefined;
    const stream = new ReadableStream<Uint8Array>({
      start(streamController) {
        controller = streamController;
        subscribers.add(streamController);
        streamController.enqueue(
          encoder.encode(`event: revision\ndata: ${getRevision()}\n\n`),
        );
        keepalive = setInterval(() => {
          try {
            streamController.enqueue(encoder.encode(": keepalive\n\n"));
          } catch {
            subscribers.delete(streamController);
            if (keepalive) clearInterval(keepalive);
          }
        }, 20_000);
      },
      cancel() {
        if (controller) subscribers.delete(controller);
        if (keepalive) clearInterval(keepalive);
      },
    });

    return new Response(stream, {
      headers: {
        "Cache-Control": "no-cache, no-transform",
        Connection: "keep-alive",
        "Content-Type": "text/event-stream",
        "X-Accel-Buffering": "no",
      },
    });
  }

  async function handle(request: Request): Promise<Response> {
    try {
      const url = new URL(request.url);
      const path = url.pathname;

      if (request.method === "GET" && path === `${API_PREFIX}/health`) {
        return json({ status: "ok" });
      }
      if (request.method === "GET" && path === `${API_PREFIX}/tasks`) {
        return json(getState());
      }
      if (request.method === "GET" && path === `${API_PREFIX}/events`) {
        return eventStream();
      }

      requireAllowedOrigin(request);
      const body = await parseBody(request);

      let revision: number;
      if (request.method === "POST" && path === `${API_PREFIX}/tasks`) {
        revision = createTask(parseText(body.text), parseRevision(body.revision));
      } else if (request.method === "PUT" && path === `${API_PREFIX}/tasks`) {
        if (!Array.isArray(body.tasks)) {
          throw new ApiError(400, "invalid_request", "tasks must be an array");
        }
        const tasks = body.tasks.map((value) => {
          if (
            !isObject(value) ||
            typeof value.id !== "string" ||
            value.id.length === 0 ||
            typeof value.checked !== "boolean"
          ) {
            throw new ApiError(400, "invalid_request", "Each task is invalid");
          }
          return {
            id: value.id,
            text: parseText(value.text),
            checked: value.checked,
          };
        });
        revision = replaceTasks(tasks, parseRevision(body.revision));
      } else if (request.method === "PUT" && path === `${API_PREFIX}/tasks/order`) {
        if (
          !Array.isArray(body.taskIds) ||
          body.taskIds.some((id) => typeof id !== "string")
        ) {
          throw new ApiError(400, "invalid_request", "taskIds must be an array of strings");
        }
        revision = reorderTasks(body.taskIds, parseRevision(body.revision));
      } else {
        const taskMatch = path.match(/^\/api\/shared-todo\/tasks\/([^/]+)$/);
        if (!taskMatch) {
          throw new ApiError(404, "not_found", "Endpoint not found");
        }

        const id = decodeURIComponent(taskMatch[1]);
        if (request.method === "PATCH") {
          revision = updateTask(id, body, parseRevision(body.revision));
        } else if (request.method === "DELETE") {
          revision = deleteTask(id, parseRevision(body.revision));
        } else {
          throw new ApiError(404, "not_found", "Endpoint not found");
        }
      }

      publishRevision(revision);
      return json(getState());
    } catch (error) {
      return errorResponse(error);
    }
  }

  return {
    close() {
      for (const subscriber of subscribers) subscriber.close();
      subscribers.clear();
      database.close();
    },
    getState,
    handle,
  };
}
