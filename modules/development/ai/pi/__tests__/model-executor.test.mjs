import assert from "node:assert/strict";
import { spawnSync } from "node:child_process";
import { once } from "node:events";
import { mkdir, mkdtemp, readFile, rm, symlink, writeFile } from "node:fs/promises";
import { createServer as createHttpServer } from "node:http";
import { createServer } from "node:net";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { after, test } from "node:test";
import { pathToFileURL } from "node:url";

// Catalog refreshes must stay local: these tests contact only loopback fixtures.
process.env.PI_OFFLINE = "1";
const root = process.env.PI_TEST_PACKAGE;
assert.ok(root, "PI_TEST_PACKAGE must point to the unpacked package with dependencies");
const load = (path) => import(pathToFileURL(join(root, "dist", path)).href);
const { ModelRuntime } = await load("core/model-runtime.js");
const { AuthStorage } = await load("core/auth-storage.js");
const { ModelExecutorClient, serveModelExecutor } = await load("core/model-executor.js");
const { ExecutorAuthStorageBackend } = await load("core/executor-credentials.js");

// Synthetic credentials only: these never leave the test's loopback servers.
const API_KEY = "sk-ant-api03-synthetic-executor-key-0123456789";
const PROFILE_KEY = "sk-ant-api03-synthetic-profile-key-0123456789";
const OAUTH_ACCESS = "sk-ant-oat01-synthetic-executor-access-0123456789";
const OAUTH_REFRESH = "sk-ant-ort01-synthetic-executor-refresh-0123456789";
const ROTATED_ACCESS = "synthetic-rotated-access-token-0123456789";
const ROTATED_REFRESH = "synthetic-rotated-refresh-token-0123456789";
const HEADER_TOKEN = "synthetic-configured-header-token-0123456789";
const secrets = [API_KEY, PROFILE_KEY, OAUTH_ACCESS, OAUTH_REFRESH, ROTATED_ACCESS, ROTATED_REFRESH, HEADER_TOKEN];

const cleanup = [];
after(async () => {
  for (const step of cleanup.reverse()) await step();
});

function sse(events) {
  return events.map(([event, data]) => `event: ${event}\ndata: ${JSON.stringify(data)}\n\n`).join("");
}

const reply = sse([
  ["message_start", { type: "message_start", message: { id: "msg_fixture", type: "message", role: "assistant", model: "fixture", content: [], stop_reason: null, stop_sequence: null, usage: { input_tokens: 3, output_tokens: 1 } } }],
  ["content_block_start", { type: "content_block_start", index: 0, content_block: { type: "text", text: "" } }],
  ["content_block_delta", { type: "content_block_delta", index: 0, delta: { type: "text_delta", text: "Hel" } }],
  ["content_block_delta", { type: "content_block_delta", index: 0, delta: { type: "text_delta", text: "lo" } }],
  ["content_block_stop", { type: "content_block_stop", index: 0 }],
  ["message_delta", { type: "message_delta", delta: { stop_reason: "end_turn", stop_sequence: null }, usage: { output_tokens: 2 } }],
  ["message_stop", { type: "message_stop" }],
]);

/** A loopback server standing in for Anthropic messages, a usage endpoint, and a Radius token endpoint. */
async function provider({ hold = false } = {}) {
  const requests = [];
  const server = createHttpServer((request, response) => {
    const chunks = [];
    request.on("data", (chunk) => chunks.push(chunk));
    request.on("end", () => {
      const text = Buffer.concat(chunks).toString("utf8");
      const entry = { url: request.url, headers: request.headers, text };
      requests.push(entry);
      if (request.url === "/v1/oauth/token") {
        response.writeHead(200, { "content-type": "application/json" });
        return response.end(JSON.stringify({ access_token: ROTATED_ACCESS, refresh_token: ROTATED_REFRESH, expires_in: 3600 }));
      }
      if (request.url === "/usage") {
        response.writeHead(200, { "content-type": "application/json" });
        return response.end(JSON.stringify({ ok: true }));
      }
      entry.body = JSON.parse(text);
      response.writeHead(200, { "content-type": "text/event-stream", "x-fixture-response": "seen" });
      if (!hold) return response.end(reply);
      // Stream the first event, then wait until the client goes away.
      entry.closed = once(response, "close");
      response.write(reply.slice(0, reply.indexOf("event: content_block_start")));
    });
  });
  server.listen(0, "127.0.0.1");
  await once(server, "listening");
  cleanup.push(() => new Promise((resolve) => { server.closeAllConnections(); server.close(resolve); }));
  return { baseUrl: `http://127.0.0.1:${server.address().port}`, requests };
}

/**
 * A host executor over a disposable agent directory, and a sandbox-side runtime whose credential
 * store is an executor-held file: the sandbox never opens a credential file itself.
 */
async function fixture(files, { hold = false, store = "auth.json" } = {}) {
  const upstream = await provider({ hold });
  const dir = await mkdtemp(join(tmpdir(), "pi-model-executor-"));
  cleanup.push(() => rm(dir, { recursive: true, force: true }));
  const agent = join(dir, "agent");
  await mkdir(join(agent, "auth-profiles"), { recursive: true });
  const modelsPath = join(agent, "models.json");
  await writeFile(modelsPath, JSON.stringify({
    providers: {
      anthropic: { baseUrl: upstream.baseUrl, headers: { "x-fixture-token": HEADER_TOKEN } },
      "fixture-radius": { name: "Fixture Radius", oauth: "radius", baseUrl: `${upstream.baseUrl}/v1` },
    },
  }));
  for (const [name, content] of Object.entries(files)) {
    await writeFile(join(agent, name), JSON.stringify(content), { mode: 0o600 });
  }
  const host = await ModelRuntime.create({
    credentials: AuthStorage.create(join(agent, "auth.json")),
    modelsPath,
    executorSocket: null,
    allowModelNetwork: false,
  });
  const socketPath = join(dir, "executor.sock");
  const server = createServer();
  serveModelExecutor(host, server, { agentDir: agent });
  server.listen(socketPath);
  await once(server, "listening");
  cleanup.push(() => new Promise((resolve) => server.close(resolve)));
  const client = new ModelExecutorClient(socketPath);
  const storeFor = (name) => AuthStorage.fromStorage(new ExecutorAuthStorageBackend(client, join(agent, name)));
  const sandbox = await ModelRuntime.create({ credentials: storeFor(store), modelsPath, executorSocket: socketPath, allowModelNetwork: false });
  const model = sandbox.getModels("anthropic").find((candidate) => candidate.api === "anthropic-messages");
  assert.ok(model, "the built-in catalog provides an Anthropic messages model");
  const readHost = async (name) => JSON.parse(await readFile(join(agent, name), "utf8"));
  return { upstream, sandbox, model, client, storeFor, agent, dir, modelsPath, readHost };
}

const context = { systemPrompt: "Fixture system prompt.", messages: [{ role: "user", content: "Say hello.", timestamp: Date.now() }] };

async function run(sandbox, model, extra = {}) {
  const observed = [];
  const stream = sandbox.streamSimple(model, context, {
    sessionId: "fixture-session",
    headers: { "x-api-key": "sandbox-forged-key", "x-sandbox-option": "kept" },
    transformHeaders: async (headers) => {
      observed.push({ headers });
      return { ...headers, "x-api-key": "sandbox-forged-key", authorization: "Bearer sandbox-forged", "x-from-extension": "1" };
    },
    onPayload: async (payload) => {
      observed.push({ payload });
      return { ...payload, metadata: { user_id: "fixture-user" } };
    },
    onResponse: async (response) => observed.push({ response }),
    onProviderStreamEvent: async (data) => observed.push({ providerEvent: data }),
    ...extra,
  });
  const events = [];
  for await (const event of stream) events.push(event);
  const message = await stream.result();
  return { observed, events, message };
}

function assertNoSecrets(value) {
  const text = typeof value === "string" ? value : JSON.stringify(value);
  for (const secret of secrets) assert.equal(text.includes(secret), false, "sandbox-visible data contains a credential");
}

test("credential files read through the executor hold references, not secrets", async () => {
  const { sandbox, storeFor } = await fixture({
    "auth.json": { anthropic: { type: "api_key", key: API_KEY } },
    "auth-profiles/ct.json": { anthropic: { type: "oauth", access: OAUTH_ACCESS, refresh: OAUTH_REFRESH, expires: 4102444800000, accountId: "fixture-account" } },
  });
  const key = await storeFor("auth.json").read("anthropic");
  assert.equal(key.type, "api_key");
  assert.match(key.key, /^piref_/);
  const oauth = await storeFor("auth-profiles/ct.json").read("anthropic");
  assert.equal(oauth.accountId, "fixture-account");
  assert.equal(oauth.expires, 4102444800000);
  assert.match(oauth.access, /^piref_/);
  assert.match(oauth.refresh, /^piref_/);
  assert.deepEqual(await storeFor("auth-profiles/ct.json").list(), [{ providerId: "anthropic", type: "oauth" }]);
  const auth = await sandbox.getAuth("anthropic");
  assert.match(auth.auth.apiKey, /^piref_/);
  assertNoSecrets({ key, oauth, auth });
});

test("API-key requests use the sandbox's chosen credential through the executor", async () => {
  const { upstream, sandbox, model } = await fixture({ "auth.json": { anthropic: { type: "api_key", key: API_KEY } } });
  const { observed, events, message } = await run(sandbox, model);
  assert.equal(message.stopReason, "stop", message.errorMessage);
  assert.equal(message.content.map((block) => block.text).join(""), "Hello");
  assert.deepEqual(events.map((event) => event.type), ["start", "text_start", "text_delta", "text_delta", "text_end", "done"]);
  assert.equal(events[2].partial, events[5].message, "deltas update the same live message as the final result");
  assert.equal(upstream.requests.length, 1);
  const [request] = upstream.requests;
  assert.equal(request.headers["x-api-key"], API_KEY);
  assert.equal(request.headers.authorization, undefined);
  assert.equal(request.headers["x-fixture-token"], HEADER_TOKEN);
  assert.equal(request.headers["x-sandbox-option"], "kept");
  assert.equal(request.headers["x-from-extension"], "1");
  assert.deepEqual(request.body.metadata, { user_id: "fixture-user" });
  assert.equal(observed.find((entry) => entry.headers)?.headers["x-fixture-token"], "[redacted]");
  assert.equal(observed.find((entry) => entry.response)?.response.status, 200);
  assertNoSecrets({ observed, events, message });
});

test("a profile file chosen in the sandbox is the credential the provider receives", async () => {
  const { upstream, sandbox, model } = await fixture(
    {
      "auth.json": { anthropic: { type: "api_key", key: API_KEY } },
      "auth-profiles/ct.json": { anthropic: { type: "api_key", key: PROFILE_KEY } },
    },
    { store: "auth-profiles/ct.json" },
  );
  const { message } = await run(sandbox, model);
  assert.equal(message.stopReason, "stop", message.errorMessage);
  assert.equal(upstream.requests[0].headers["x-api-key"], PROFILE_KEY);
});

test("Anthropic OAuth requests carry the executor's bearer token", async () => {
  const { upstream, sandbox, model } = await fixture({
    "auth.json": { anthropic: { type: "oauth", access: OAUTH_ACCESS, refresh: OAUTH_REFRESH, expires: Date.now() + 3_600_000 } },
  });
  const { observed, events, message } = await run(sandbox, model);
  assert.equal(message.stopReason, "stop", message.errorMessage);
  assert.equal(upstream.requests[0].headers.authorization, `Bearer ${OAUTH_ACCESS}`);
  assert.notEqual(upstream.requests[0].headers["x-api-key"], "sandbox-forged-key");
  assertNoSecrets({ observed, events, message });
});

test("OAuth refresh runs on the executor and persists the rotated tokens on the host", async () => {
  const { upstream, sandbox, readHost } = await fixture({
    "auth.json": { "fixture-radius": { type: "oauth", access: "synthetic-expired-access-0123456789", refresh: OAUTH_REFRESH, expires: Date.now() - 1_000 } },
  });
  const auth = await sandbox.getAuth("fixture-radius");
  assert.match(auth.auth.apiKey, /^piref_/);
  const token = upstream.requests.find((request) => request.url === "/v1/oauth/token");
  assert.ok(token, "the executor called the token endpoint");
  assert.equal(new URLSearchParams(token.text).get("refresh_token"), OAUTH_REFRESH);
  const stored = (await readHost("auth.json"))["fixture-radius"];
  assert.equal(stored.access, ROTATED_ACCESS);
  assert.equal(stored.refresh, ROTATED_REFRESH);
  assertNoSecrets(auth);
});

test("sandbox writes keep the stored secrets and cannot move one provider's secret to another", async () => {
  const { storeFor, readHost } = await fixture({ "auth.json": { anthropic: { type: "api_key", key: API_KEY } } });
  const store = storeFor("auth.json");
  await store.modify("anthropic", async (current) => ({ ...current, env: { FIXTURE_REGION: "eu" } }));
  assert.deepEqual((await readHost("auth.json")).anthropic, { type: "api_key", key: API_KEY, env: { FIXTURE_REGION: "eu" } });
  const reference = (await store.read("anthropic")).key;
  await assert.rejects(
    store.modify("openai", async () => ({ type: "api_key", key: reference })),
    /does not belong to openai/,
  );
  assert.equal((await readHost("auth.json")).openai, undefined);
});

test("references in fetch headers reach only the credential provider's origins", async () => {
  const { upstream, sandbox, storeFor } = await fixture({
    "auth.json": { anthropic: { type: "oauth", access: OAUTH_ACCESS, refresh: OAUTH_REFRESH, expires: Date.now() + 3_600_000 } },
  });
  const other = await provider();
  const auth = await sandbox.getAuth("anthropic");
  const response = await fetch(`${upstream.baseUrl}/usage`, { headers: { authorization: `Bearer ${auth.auth.apiKey}` } });
  assert.equal(response.status, 200);
  assert.deepEqual(await response.json(), { ok: true });
  assert.equal(upstream.requests.at(-1).headers.authorization, `Bearer ${OAUTH_ACCESS}`);
  await assert.rejects(fetch(`${other.baseUrl}/usage`, { headers: { authorization: `Bearer ${auth.auth.apiKey}` } }), /cannot be sent to/);
  const refresh = (await storeFor("auth.json").read("anthropic")).refresh;
  await assert.rejects(fetch(`${upstream.baseUrl}/usage`, { headers: { authorization: `Bearer ${refresh}` } }), /Refresh tokens cannot be sent/);
  assert.equal(other.requests.length, 0);
});

test("the executor opens only the agent directory's credential files", async () => {
  const { client, agent, dir } = await fixture({ "auth.json": {} });
  const outside = join(dir, "outside.json");
  await writeFile(outside, JSON.stringify({ anthropic: { type: "api_key", key: API_KEY } }));
  await symlink(outside, join(agent, "auth-profiles", "linked.json"));
  for (const path of [outside, join(agent, "auth-profiles", "linked.json"), join(agent, "models.json"), "/etc/passwd"]) {
    await assert.rejects(client.lockCredentialFile(path, async (content) => ({ result: content })), /outside the agent directory/);
  }
});

test("the executor resolves models from its own catalog and rejects unknown models before contacting a provider", async () => {
  const { upstream, sandbox, model } = await fixture({ "auth.json": { anthropic: { type: "api_key", key: API_KEY } } });
  const { message } = await run(sandbox, { ...model, id: "fixture-unknown-model", baseUrl: "http://127.0.0.1:9" });
  assert.equal(message.stopReason, "error");
  assert.match(message.errorMessage, /Unknown model: anthropic\/fixture-unknown-model/);
  assert.equal(upstream.requests.length, 0);
  const redirected = await run(sandbox, { ...model, baseUrl: "http://127.0.0.1:9" });
  assert.equal(redirected.message.stopReason, "stop", redirected.message.errorMessage);
  assert.equal(upstream.requests.length, 1, "a sandbox-supplied baseUrl does not redirect the request");
});

test("callback failures in the sandbox fail the request without exposing credentials", async () => {
  const { upstream, sandbox, model } = await fixture({ "auth.json": { anthropic: { type: "api_key", key: API_KEY } } });
  const { message } = await run(sandbox, model, {
    onPayload: async () => {
      throw new Error("fixture payload rejection");
    },
  });
  assert.equal(message.stopReason, "error");
  assert.match(message.errorMessage, /fixture payload rejection/);
  assert.equal(upstream.requests.length, 0);
  assertNoSecrets(message);
});

test("aborting in the sandbox cancels the executor's provider request", async () => {
  const { upstream, sandbox, model } = await fixture({ "auth.json": { anthropic: { type: "api_key", key: API_KEY } } }, { hold: true });
  const controller = new AbortController();
  const stream = sandbox.streamSimple(model, context, { signal: controller.signal });
  for await (const event of stream) {
    if (event.type === "start") controller.abort();
  }
  const message = await stream.result();
  assert.equal(message.stopReason, "aborted", message.errorMessage);
  assert.equal(upstream.requests.length, 1);
  await upstream.requests[0].closed;
});

test("raw mode still resolves credentials locally", async () => {
  const { agent, modelsPath } = await fixture({ "auth.json": { anthropic: { type: "api_key", key: API_KEY } } });
  const raw = await ModelRuntime.create({
    credentials: AuthStorage.create(join(agent, "auth.json")),
    modelsPath,
    executorSocket: null,
    allowModelNetwork: false,
  });
  assert.equal(raw.credentialsHeldByExecutor("anthropic"), false);
  assert.equal((await raw.getAuth("anthropic"))?.auth.apiKey, API_KEY);
});

test("pi auth refuses to run in executor mode", { skip: !process.env.PI_TEST_BINARY }, async () => {
  const { dir, agent } = await fixture({ "auth.json": { anthropic: { type: "api_key", key: API_KEY } } });
  for (const args of [["auth", "print-api-key", "anthropic"], ["auth", "check", "anthropic", "--credentials"]]) {
    const child = spawnSync(process.env.PI_TEST_BINARY, args, {
      env: { HOME: dir, PATH: process.env.PATH, PI_CODING_AGENT_DIR: agent, PI_OFFLINE: "1", PI_MODEL_EXECUTOR_SOCKET: join(dir, "executor.sock") },
      encoding: "utf8",
      timeout: 30_000,
    });
    assert.ifError(child.error);
    assert.equal(child.status, 1, child.stderr);
    assert.match(child.stderr, /unavailable in sandboxed sessions/);
    assertNoSecrets(child.stdout + child.stderr);
  }
});
