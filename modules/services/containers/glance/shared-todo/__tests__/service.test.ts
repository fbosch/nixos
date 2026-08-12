import { afterEach, describe, expect, test } from "bun:test";
import { mkdtemp, rm } from "node:fs/promises";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { createTodoService } from "../service.ts";

const ORIGIN = "https://glance.corvus-corax.synology.me";
const services: ReturnType<typeof createTodoService>[] = [];
const directories: string[] = [];

afterEach(async () => {
  for (const service of services.splice(0)) service.close();
  for (const directory of directories.splice(0)) {
    await rm(directory, { recursive: true, force: true });
  }
});

async function serviceAt(databasePath = ":memory:") {
  const service = createTodoService({ databasePath, allowedOrigin: ORIGIN });
  services.push(service);
  return service;
}

function mutation(method: string, path: string, body: unknown, origin = ORIGIN) {
  return new Request(`http://localhost${path}`, {
    method,
    headers: {
      "Content-Type": "application/json",
      Origin: origin,
    },
    body: JSON.stringify(body),
  });
}

describe("shared todo service", () => {
  test("creates, updates, reorders, and deletes tasks", async () => {
    const service = await serviceAt();

    let response = await service.handle(
      mutation("POST", "/api/shared-todo/tasks", { text: "First", revision: 0 }),
    );
    expect(response.status).toBe(200);
    let state = await response.json();
    expect(state).toMatchObject({ revision: 1, tasks: [{ text: "First", checked: false }] });

    response = await service.handle(
      mutation("POST", "/api/shared-todo/tasks", { text: "Second", revision: 1 }),
    );
    state = await response.json();
    const [first, second] = state.tasks;

    response = await service.handle(
      mutation("PATCH", `/api/shared-todo/tasks/${first.id}`, {
        checked: true,
        text: "Updated first",
        revision: 2,
      }),
    );
    expect(await response.json()).toMatchObject({
      revision: 3,
      tasks: [{ text: "Updated first", checked: true }, { text: "Second" }],
    });

    response = await service.handle(
      mutation("PUT", "/api/shared-todo/tasks/order", {
        taskIds: [second.id, first.id],
        revision: 3,
      }),
    );
    expect((await response.json()).tasks.map((task: { id: string }) => task.id)).toEqual([
      second.id,
      first.id,
    ]);

    response = await service.handle(
      mutation("DELETE", `/api/shared-todo/tasks/${first.id}`, { revision: 4 }),
    );
    expect(await response.json()).toMatchObject({
      revision: 5,
      tasks: [{ id: second.id }],
    });
  });

  test("rejects stale revisions without changing state", async () => {
    const service = await serviceAt();
    await service.handle(
      mutation("POST", "/api/shared-todo/tasks", { text: "Current", revision: 0 }),
    );

    const response = await service.handle(
      mutation("POST", "/api/shared-todo/tasks", { text: "Stale", revision: 0 }),
    );

    expect(response.status).toBe(409);
    expect(await response.json()).toMatchObject({ error: { code: "conflict" } });
    expect(service.getState()).toMatchObject({ revision: 1, tasks: [{ text: "Current" }] });
  });

  test("replaces the complete ordered list atomically", async () => {
    const service = await serviceAt();
    const response = await service.handle(
      mutation("PUT", "/api/shared-todo/tasks", {
        revision: 0,
        tasks: [
          { id: "second", text: "Second", checked: true },
          { id: "first", text: "First", checked: false },
        ],
      }),
    );

    expect(response.status).toBe(200);
    expect(await response.json()).toEqual({
      revision: 1,
      tasks: [
        { id: "second", text: "Second", checked: true },
        { id: "first", text: "First", checked: false },
      ],
    });

    const invalid = await service.handle(
      mutation("PUT", "/api/shared-todo/tasks", {
        revision: 1,
        tasks: [
          { id: "duplicate", text: "One", checked: false },
          { id: "duplicate", text: "Two", checked: false },
        ],
      }),
    );
    expect(invalid.status).toBe(400);
    expect(service.getState().revision).toBe(1);
  });

  test("validates mutation origin, content, and complete ordering", async () => {
    const service = await serviceAt();

    const crossOrigin = await service.handle(
      mutation(
        "POST",
        "/api/shared-todo/tasks",
        { text: "Blocked", revision: 0 },
        "https://attacker.example",
      ),
    );
    expect(crossOrigin.status).toBe(403);

    const emptyText = await service.handle(
      mutation("POST", "/api/shared-todo/tasks", { text: "  ", revision: 0 }),
    );
    expect(emptyText.status).toBe(400);

    await service.handle(
      mutation("POST", "/api/shared-todo/tasks", { text: "One", revision: 0 }),
    );
    await service.handle(
      mutation("POST", "/api/shared-todo/tasks", { text: "Two", revision: 1 }),
    );
    const id = service.getState().tasks[0].id;
    const incompleteOrder = await service.handle(
      mutation("PUT", "/api/shared-todo/tasks/order", {
        taskIds: [id],
        revision: 2,
      }),
    );
    expect(incompleteOrder.status).toBe(400);
    expect(service.getState().revision).toBe(2);
  });

  test("persists tasks and revision when the database is reopened", async () => {
    const directory = await mkdtemp(join(tmpdir(), "glance-shared-todo-"));
    directories.push(directory);
    const databasePath = join(directory, "todo.sqlite");
    const first = await serviceAt(databasePath);
    await first.handle(
      mutation("POST", "/api/shared-todo/tasks", { text: "Persistent", revision: 0 }),
    );
    first.close();
    services.splice(services.indexOf(first), 1);

    const reopened = await serviceAt(databasePath);
    expect(reopened.getState()).toMatchObject({
      revision: 1,
      tasks: [{ text: "Persistent", checked: false }],
    });
  });

  test("publishes a revision event after a successful mutation", async () => {
    const service = await serviceAt();
    const events = await service.handle(
      new Request("http://localhost/api/shared-todo/events"),
    );
    const reader = events.body!.getReader();
    const decoder = new TextDecoder();
    expect(decoder.decode((await reader.read()).value)).toContain("data: 0");

    await service.handle(
      mutation("POST", "/api/shared-todo/tasks", { text: "Broadcast", revision: 0 }),
    );

    expect(decoder.decode((await reader.read()).value)).toContain("data: 1");
    await reader.cancel();
  });
});
