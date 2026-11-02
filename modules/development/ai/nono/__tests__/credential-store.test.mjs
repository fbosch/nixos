import assert from "node:assert/strict";
import { once } from "node:events";
import { lstatSync, mkdirSync, mkdtempSync, readFileSync, readlinkSync, realpathSync, rmSync, statSync, symlinkSync, utimesSync, writeFileSync } from "node:fs";
import { createServer } from "node:net";
import { dirname, join } from "node:path";
import { afterEach, test } from "node:test";
import { agentProtection, prepareAgentRuntime } from "../scripts/agent-protection.mjs";
import { credentialFilesOutsideStore, credentialStoreDirectory, migrateCredentialStore, runningSandboxes } from "../scripts/credential-store.mjs";
import { launchArguments } from "../scripts/launcher.mjs";

const envBinary = process.env.ENV_TEST_BINARY ?? "/usr/bin/env";
const created = [];
afterEach(() => { for (const path of created.splice(0)) rmSync(path, { recursive: true, force: true }); });

// Synthetic credential content only.
const AUTH = JSON.stringify({ anthropic: { type: "api_key", key: "synthetic-default-key" } });
const CT = JSON.stringify({ anthropic: { type: "oauth", access: "synthetic-ct-access", refresh: "synthetic-ct-refresh", expires: 1 } });

function fixture() {
  // Short roots keep Unix socket paths below the macOS sockaddr_un limit.
  const root = realpathSync(mkdtempSync("/tmp/pi-cs-"));
  created.push(root);
  const home = join(root, "home");
  const agent = join(home, "dotfiles", ".pi", "agent");
  const defaultAgent = join(home, ".pi", "agent");
  const cwd = join(root, "work");
  for (const path of [agent, defaultAgent, cwd]) mkdirSync(path, { recursive: true });
  prepareAgentRuntime(agent);
  writeFileSync(join(agent, "auth.json"), AUTH, { mode: 0o600 });
  writeFileSync(join(agent, "auth-profiles", "ct.json"), CT, { mode: 0o600 });
  writeFileSync(join(agent, "auth-profiles", "Archive.zip"), "not a profile");
  // Stow links the default agent directory's auth.json to the configured one.
  symlinkSync(join("..", "..", "dotfiles", ".pi", "agent", "auth.json"), join(defaultAgent, "auth.json"));
  const profile = join(root, "pi.json");
  writeFileSync(profile, "{}");
  return { root, home, agent, defaultAgent, cwd, profile, store: join(home, ".local", "share", "pi-credentials") };
}

function values(args, flag) {
  return args.flatMap((part, index) => part === flag ? [args[index + 1]] : []);
}

async function withSocket(home, run) {
  const directory = join(home, ".pi-ipc", "model-cs");
  mkdirSync(directory, { recursive: true, mode: 0o700 });
  const socket = join(directory, "s");
  const server = createServer(connection => connection.end());
  server.listen(socket);
  await once(server, "listening");
  try { return await run(socket); } finally { await new Promise(resolve => server.close(resolve)); }
}

test("an existing setup moves into the private store and keeps working through relative links", () => {
  const f = fixture();
  const { store, warnings } = migrateCredentialStore(f.home, f.agent);
  assert.equal(store, f.store);
  assert.deepEqual(warnings, []);
  for (const [path, target, content] of [
    [join(f.agent, "auth.json"), join(store, "auth.json"), AUTH],
    [join(f.agent, "auth-profiles", "ct.json"), join(store, "auth-profiles", "ct.json"), CT],
  ]) {
    assert.ok(lstatSync(path).isSymbolicLink(), path);
    assert.ok(!readlinkSync(path).startsWith("/"), "links are relative so Stow accepts them");
    assert.equal(realpathSync(path), target);
    assert.equal(readFileSync(path, "utf8"), content, "the old path still reads the same credentials");
    assert.equal(statSync(target).mode & 0o777, 0o600);
  }
  assert.equal(readFileSync(join(f.defaultAgent, "auth.json"), "utf8"), AUTH, "the Stow link resolves through the store");
  for (const path of [store, join(store, "auth-profiles")]) assert.equal(statSync(path).mode & 0o777, 0o700);
  assert.ok(lstatSync(join(f.agent, "auth-profiles", "Archive.zip")).isFile(), "non-profile files stay where they are");
  assert.deepEqual(migrateCredentialStore(f.home, f.agent).warnings, [], "a second launch changes nothing");
  assert.deepEqual(credentialFilesOutsideStore([f.agent, f.defaultAgent]), []);
});

test("files that cannot move safely stay in place with a warning", () => {
  const f = fixture();
  const store = credentialStoreDirectory(f.home);
  mkdirSync(join(store, "auth-profiles"), { recursive: true, mode: 0o700 });
  writeFileSync(join(store, "auth-profiles", "ct.json"), "{}", { mode: 0o600 });
  writeFileSync(join(f.root, "elsewhere.json"), "{}");
  symlinkSync(join(f.root, "elsewhere.json"), join(f.agent, "auth-profiles", "planted.json"));
  const { warnings } = migrateCredentialStore(f.home, f.agent);
  assert.equal(readFileSync(join(f.agent, "auth-profiles", "ct.json"), "utf8"), CT);
  assert.ok(lstatSync(join(f.agent, "auth-profiles", "ct.json")).isFile());
  assert.equal(readFileSync(join(store, "auth-profiles", "ct.json"), "utf8"), "{}");
  assert.equal(realpathSync(join(f.agent, "auth-profiles", "planted.json")), join(f.root, "elsewhere.json"));
  assert.ok(warnings.some(warning => warning.includes("ct.json differs")), warnings.join("\n"));
  assert.ok(warnings.some(warning => warning.includes("planted.json links to")), warnings.join("\n"));
  assert.ok(lstatSync(join(f.agent, "auth.json")).isSymbolicLink(), "other files still move");
  assert.deepEqual(credentialFilesOutsideStore([f.agent]), [join(f.agent, "auth-profiles", "ct.json")]);
});

test("a file locked by a running Pi moves on a later launch; stale locks are taken over", () => {
  const f = fixture();
  const lock = join(f.agent, "auth-profiles", "ct.json.lock");
  mkdirSync(lock);
  assert.ok(migrateCredentialStore(f.home, f.agent).warnings.some(warning => warning.includes("locked")));
  assert.ok(lstatSync(join(f.agent, "auth-profiles", "ct.json")).isFile());
  const old = new Date(Date.now() - 120_000);
  utimesSync(lock, old, old);
  assert.deepEqual(migrateCredentialStore(f.home, f.agent).warnings, []);
  assert.ok(lstatSync(join(f.agent, "auth-profiles", "ct.json")).isSymbolicLink());
});

test("a missing auth.json is created in the store", () => {
  const f = fixture();
  rmSync(join(f.agent, "auth.json"));
  migrateCredentialStore(f.home, f.agent);
  assert.equal(realpathSync(join(f.agent, "auth.json")), join(f.store, "auth.json"));
  assert.equal(readFileSync(join(f.store, "auth.json"), "utf8"), "{}");
});

test("migrated links pass agent protection, and only executor-free sessions are granted the store", async () => {
  const f = fixture();
  migrateCredentialStore(f.home, f.agent);
  assert.doesNotThrow(() => agentProtection(f.home, f.agent));
  const writable = (args) => [...values(args, "--allow"), ...values(args, "--allow-file")];
  const ordinary = launchArguments(f.cwd, f.agent, f.home, {}, f.profile, process.execPath, envBinary, "darwin");
  assert.ok(writable(ordinary).includes(join(f.store, "auth.json")));
  assert.ok(writable(ordinary).includes(join(f.store, "auth-profiles")));
  await withSocket(f.home, async socket => {
    for (const platform of ["darwin", "linux"]) {
      const args = launchArguments(f.cwd, f.agent, f.home, { PI_MODEL_EXECUTOR_SOCKET: socket }, f.profile, process.execPath, envBinary, platform);
      const grants = [...writable(args), ...values(args, "--read"), ...values(args, "--read-file")];
      assert.deepEqual(grants.filter(path => path.startsWith(f.store)), [], platform);
    }
  });
});

test("a grant that would reach the store is refused in executor mode", async () => {
  const f = fixture();
  migrateCredentialStore(f.home, f.agent);
  const share = dirname(f.store);
  await withSocket(f.home, async socket => {
    assert.throws(
      () => launchArguments(share, f.agent, f.home, { PI_MODEL_EXECUTOR_SOCKET: socket }, f.profile, process.execPath, envBinary, "darwin"),
      /credential store overlaps a Pi sandbox grant/,
    );
  });
});

test("migration waits for running sandboxes, which were granted the old paths", () => {
  const list = () => [
    { pid: 10, argv: ["/nix/store/x-nono-0.80.0/bin/nono", "run", "--profile", "p.json"] },
    { pid: 11, argv: ["/nix/store/x-nono-0.80.0/bin/nono", "setup"] },
    { pid: 12, argv: ["/usr/bin/node", "launcher.mjs", "nono", "run"] },
  ];
  assert.deepEqual(runningSandboxes("linux", list), [10]);
  assert.deepEqual(runningSandboxes("darwin", () => []), []);
  assert.equal(runningSandboxes("darwin", () => undefined), undefined, "an unreadable process list postpones migration");
});
