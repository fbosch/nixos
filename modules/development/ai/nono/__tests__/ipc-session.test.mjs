import assert from "node:assert/strict";
import { once } from "node:events";
import { existsSync, mkdirSync, mkdtempSync, readdirSync, realpathSync, rmSync, writeFileSync } from "node:fs";
import { createConnection, createServer } from "node:net";
import { join } from "node:path";
import { test } from "node:test";
import { defaultCapabilities, validateCapabilities } from "../scripts/ipc-policy.mjs";
import { withIpcCapabilities } from "../scripts/ipc-session.mjs";
import { launchArguments } from "../scripts/launcher.mjs";
import { echoRegistry } from "./fixtures/ipc-registry.mjs";

function exchange(endpoint, request) {
  return new Promise((resolve, reject) => {
    const client = createConnection(endpoint); let data = "";
    client.setTimeout(3000, () => client.destroy(new Error("IPC fixture timed out")));
    client.once("error", reject);
    client.once("connect", () => client.write(JSON.stringify(request) + "\n"));
    client.on("data", chunk => {
      data += chunk.toString(); if (!data.includes("\n")) return;
      client.destroy();
      try { resolve(JSON.parse(data)); } catch (error) { reject(error); }
    });
  });
}

async function fixture(run) {
  const root = realpathSync(mkdtempSync("/tmp/pi-ipc-session-"));
  const home = join(root, "home"); const cwd = join(root, "work"); const agent = join(home, ".pi", "agent");
  mkdirSync(agent, { recursive: true }); mkdirSync(cwd);
  const upstream = join(root, "upstream"); const received = [];
  const host = createServer(client => client.on("data", chunk => {
    received.push(JSON.parse(chunk.toString())); client.end('{"ok":true}\n');
  }));
  try {
    host.listen(upstream); await once(host, "listening");
    await run({ root, home, cwd, agent, upstream, received });
  } finally {
    await new Promise(resolve => host.close(resolve));
    rmSync(root, { recursive: true, force: true });
  }
}
const request = cwd => ({ id: 1, method: "echo.ping", params: { workspace: cwd } });

test("a new service starts and receives exact grants through registry data alone", async () => {
  await fixture(async f => {
    const registry = echoRegistry(); const inherited = { ECHO_SOCKET: f.upstream };
    const project = { ECHO_SOCKET: join(f.root, "forged"), PWD: "/forged" };
    let endpoint;
    await withIpcCapabilities(project, inherited, f.home, f.cwd, f.agent, [], registry, "restricted", async bound => {
      endpoint = bound.ECHO_SOCKET;
      assert.notEqual(endpoint, inherited.ECHO_SOCKET);
      assert.ok(existsSync(endpoint));
      assert.equal((await exchange(endpoint, request(f.cwd))).ok, true);
      assert.equal((await exchange(endpoint, request(project.PWD))).ok, false);
      const profile = join(f.root, "profile.json"); const raw = join(f.root, "pi");
      writeFileSync(profile, JSON.stringify({ linux: { af_unix_mediation: "pathname" } })); writeFileSync(raw, "fixture");
      const args = launchArguments(f.cwd, f.agent, f.home, bound, profile, raw, process.env.ENV_TEST_BINARY ?? "/usr/bin/env", "linux", registry);
      assert.ok(args.includes(endpoint)); assert.ok(!args.includes(f.upstream));
    });
    assert.equal(existsSync(endpoint), false);
    assert.deepEqual(f.received.map(value => value.method), ["echo.ping", "echo.release"]);
  });
});

test("disabled and absent inherited services cannot be enabled by project environment", async () => {
  await fixture(async f => {
    const registry = structuredClone(echoRegistry()); delete registry.profiles.restricted.echo;
    const disabled = validateCapabilities(registry);
    await withIpcCapabilities({ ECHO_SOCKET: f.upstream }, { ECHO_SOCKET: f.upstream }, f.home, f.cwd, f.agent, [], disabled, "restricted", bound => {
      assert.equal(bound.ECHO_SOCKET, undefined);
    });
    await withIpcCapabilities({ ECHO_SOCKET: f.upstream }, {}, f.home, f.cwd, f.agent, [], echoRegistry(), "restricted", bound => {
      assert.equal(bound.ECHO_SOCKET, undefined);
    });
    assert.deepEqual(f.received, []);
  });
});

test("project environment cannot forge Herdr authority when it was not inherited", async () => {
  await fixture(async f => {
    await withIpcCapabilities({ HERDR_ENV: "1", HERDR_SOCKET_PATH: f.upstream, HERDR_PANE_ID: "wFixture:p1" }, {}, f.home, f.cwd, f.agent, [], defaultCapabilities, "restricted", bound => {
      assert.equal(bound.HERDR_ENV, undefined); assert.equal(bound.HERDR_SOCKET_PATH, undefined); assert.equal(bound.HERDR_PANE_ID, undefined);
    });
    assert.deepEqual(f.received, []);
  });
});

test("startup failure in a later configured service tears down earlier helpers", async () => {
  await fixture(async f => {
    const registry = structuredClone(echoRegistry());
    registry.capabilities.second = { ...registry.capabilities.echo, socketEnvironment: "SECOND_SOCKET" };
    registry.profiles.restricted.second = {};
    let ran = false;
    await assert.rejects(withIpcCapabilities({}, { ECHO_SOCKET: f.upstream, SECOND_SOCKET: join(f.root, "missing") }, f.home, f.cwd, f.agent, [], validateCapabilities(registry), "restricted", () => { ran = true; }));
    assert.equal(ran, false);
    assert.deepEqual(readdirSync(join(f.home, ".pi-ipc")), []);
    assert.deepEqual(f.received, []);
  });
});
