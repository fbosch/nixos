import assert from "node:assert/strict";
import { mkdtemp, rm, writeFile } from "node:fs/promises";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { pathToFileURL } from "node:url";
import { test } from "node:test";

const root = process.env.PI_TEST_PACKAGE;
assert.ok(
  root,
  "PI_TEST_PACKAGE must point to the unpacked package with dependencies",
);
const load = (path) => import(pathToFileURL(join(root, "dist", path)).href);
const { createAgentSession } = await load("core/sdk.js");
const { createAgentSessionServices, createAgentSessionFromServices } =
  await load("core/agent-session-services.js");
const { createAgentSessionRuntime } = await load(
  "core/agent-session-runtime.js",
);
const { ModelRuntime } = await load("core/model-runtime.js");
const { AuthStorage } = await load("core/auth-storage.js");
const { SessionManager } = await load("core/session-manager.js");
const { SettingsManager } = await load("core/settings-manager.js");
const { DefaultResourceLoader } = await load("core/resource-loader.js");
const { resolveModelScope } = await load("core/model-resolver.js");

async function fixture(run) {
  const dir = await mkdtemp(join(tmpdir(), "pi-auth-startup-"));
  const events = [];
  let failOnReload = false;
  const selected = AuthStorage.inMemory({
    "openai-codex": {
      type: "oauth",
      access: `test.${Buffer.from(JSON.stringify({ "https://api.openai.com/auth": { chatgpt_account_id: "fixture-account" } })).toString("base64url")}.test`,
      refresh: "test-only-not-a-real-token",
      expires: Date.now() + 3_600_000,
      accountId: "fixture-account",
    },
  });
  const makeRuntime = () =>
    ModelRuntime.create({
      credentials: AuthStorage.inMemory(),
      modelsPath: null,
      allowModelNetwork: false,
    });
  const factory = (pi) => {
    pi.on("before_model_availability", async (event, ctx) => {
      await Promise.resolve();
      assert.equal(ctx.cwd, dir);
      assert.equal(ctx.isProjectTrusted(), false);
      assert.ok(ctx.sessionManager.getHeader()?.id);
      const profile = ctx.sessionManager
        .getBranch()
        .findLast(
          (entry) =>
            entry.type === "custom" && entry.customType === "test-profile",
        )?.data;
      events.push([
        event.type,
        event.reason,
        profile,
        event.previousSessionFile,
      ]);
      if (failOnReload && event.reason === "reload")
        throw new Error("credential binding failed during reload");
      ctx.modelRegistry.runtime.credentials.store = selected;
    });
    pi.on("session_start", (event, ctx) => {
      events.push([event.type, event.reason]);
      assert.equal(ctx.model?.provider, "openai-codex");
    });
  };
  const settings = () =>
    SettingsManager.create(dir, dir, { projectTrusted: false });
  try {
    await run({ dir, events, factory, makeRuntime, settings, setReloadFailure: () => { failOnReload = true; } });
  } finally {
    await rm(dir, { recursive: true, force: true });
  }
}

test("standalone SDK awaits auth binding before default and restored selection", async () => {
  await fixture(async ({ dir, events, factory, makeRuntime, settings }) => {
    for (const restored of [false, true]) {
      const sm = SessionManager.inMemory(dir);
      sm.appendCustomEntry(
        "test-profile",
        restored ? "session-override" : "host-default",
      );
      if (restored) {
        sm.appendModelChange("openai-codex", "gpt-6.1-sol");
        sm.appendMessage({ role: "user", content: "fixture", timestamp: 1 });
      }
      const modelRuntime = await makeRuntime();
      const settingsManager = settings();
      const resourceLoader = new DefaultResourceLoader({
        cwd: dir,
        agentDir: dir,
        settingsManager,
        noExtensions: true,
        noSkills: true,
        extensionFactories: [factory],
      });
      await resourceLoader.reload();
      const { session, modelFallbackMessage } = await createAgentSession({
        cwd: dir,
        agentDir: dir,
        modelRuntime,
        settingsManager,
        resourceLoader,
        sessionManager: sm,
      });
      assert.equal(session.model?.provider, "openai-codex");
      assert.equal(modelFallbackMessage, undefined);
      await session.bindExtensions({});
      session.dispose();
    }
    assert.deepEqual(
      events.map((e) => e.slice(0, 3)),
      [
        ["before_model_availability", "startup", "host-default"],
        ["session_start", "startup"],
        ["before_model_availability", "startup", "session-override"],
        ["session_start", "startup"],
      ],
    );
  });
});

test("CLI service ordering, replacement metadata, and reload before callback", async () => {
  await fixture(async ({ dir, events, factory, makeRuntime, settings, setReloadFailure }) => {
    const createRuntime = async ({ sessionManager, sessionStartEvent }) => {
      const services = await createAgentSessionServices({
        cwd: dir,
        agentDir: dir,
        modelRuntime: await makeRuntime(),
        settingsManager: settings(),
        sessionManager,
        sessionStartEvent,
        resourceLoaderOptions: {
          noExtensions: true,
          noSkills: true,
          extensionFactories: [factory],
        },
      });
      // This is the CLI's pre-SDK model-scope resolution seam.
      const scope = await resolveModelScope(
        ["openai-codex/*"],
        services.modelRuntime,
      );
      assert.ok(
        scope.length > 0,
        "selected profile must be visible before CLI scope resolution",
      );
      const created = await createAgentSessionFromServices({
        services,
        sessionManager,
        sessionStartEvent,
      });
      return { ...created, services, diagnostics: [] };
    };
    const sm = SessionManager.inMemory(dir);
    sm.appendCustomEntry("test-profile", "session-override");
    const runtime = await createAgentSessionRuntime(createRuntime, {
      cwd: dir,
      agentDir: dir,
      sessionManager: sm,
    });
    runtime.setRebindSession((session) =>
      session.bindExtensions({
        onError: (error) => {
          throw new Error(error.error);
        },
      }),
    );
    await runtime.session.bindExtensions({
      onError: (error) => {
        throw new Error(error.error);
      },
    });
    await runtime.newSession();
    const resumeFile = join(dir, "resume.jsonl");
    await writeFile(
      resumeFile,
      [
        {
          type: "session",
          version: 3,
          id: "resume-fixture",
          timestamp: new Date(0).toISOString(),
          cwd: dir,
        },
        {
          type: "custom",
          id: "profile",
          parentId: null,
          timestamp: new Date(1).toISOString(),
          customType: "test-profile",
          data: "resumed-override",
        },
        {
          type: "model_change",
          id: "model",
          parentId: "profile",
          timestamp: new Date(2).toISOString(),
          provider: "openai-codex",
          modelId: "gpt-6.1-sol",
        },
        {
          type: "message",
          id: "user",
          parentId: "model",
          timestamp: new Date(3).toISOString(),
          message: { role: "user", content: "fixture", timestamp: 3 },
        },
      ]
        .map((entry) => JSON.stringify(entry))
        .join("\n") + "\n",
    );
    await runtime.switchSession(resumeFile);
    assert.equal(runtime.session.model.id, "gpt-6.1-sol");
    await runtime.fork("user", { position: "at" });
    assert.equal(events.at(-2)[3], resumeFile);
    await runtime.session.reload({
      beforeSessionStart: () => {
        assert.equal(events.at(-1)[0], "before_model_availability");
        assert.equal(events.at(-1)[1], "reload");
        assert.ok(
          runtime.session.modelRuntime
            .getAvailableSnapshot()
            .some((m) => m.provider === "openai-codex"),
        );
      },
    });
    assert.deepEqual(
      events.map((e) => e.slice(0, 3)),
      [
        ["before_model_availability", "startup", "session-override"],
        ["session_start", "startup"],
        ["before_model_availability", "new", undefined],
        ["session_start", "new"],
        ["before_model_availability", "resume", "resumed-override"],
        ["session_start", "resume"],
        ["before_model_availability", "fork", "resumed-override"],
        ["session_start", "fork"],
        ["before_model_availability", "reload", "resumed-override"],
        ["session_start", "reload"],
      ],
    );
    await runtime.session.bindExtensions({ onError: () => {} });
    setReloadFailure();
    const modelRuntime = runtime.session.modelRuntime;
    const refresh = modelRuntime.refresh.bind(modelRuntime);
    let refreshCalls = 0;
    modelRuntime.refresh = async (...args) => {
      refreshCalls++;
      return refresh(...args);
    };
    let reloadCallbackRan = false;
    await assert.rejects(
      runtime.session.reload({
        beforeSessionStart: () => { reloadCallbackRan = true; },
      }),
      /Could not prepare model availability/,
    );
    assert.equal(refreshCalls, 0, "auth hook failure must stop model availability refresh");
    assert.equal(reloadCallbackRan, false, "auth hook failure must stop reload continuation");
    await runtime.dispose();
  });
});
