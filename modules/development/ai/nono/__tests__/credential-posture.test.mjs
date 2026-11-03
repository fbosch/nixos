import assert from "node:assert/strict";
import { mkdirSync, mkdtempSync, realpathSync, rmSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { test } from "node:test";
import * as Effect from "effect/Effect";
import { assertCredentialPosture, credentialPosture, hostOnlyCredentials, writableRuntimePath } from "../scripts/launch/credential-posture.mts";
import { MODEL_EXECUTOR_SOCKET } from "../scripts/model-executor/launch.mts";
import { grant, grantPlan } from "../scripts/shared/grant-plan.mts";

const noAgentProtection = { protectedPaths: [], runtimePaths: [], authFiles: [] };

function fixture(t) {
  const root = realpathSync(mkdtempSync(join(tmpdir(), "pi-credential-posture-")));
  t.after(() => rmSync(root, { recursive: true, force: true }));
  const home = join(root, "home");
  const agent = join(home, ".pi", "agent");
  const store = join(home, ".local", "share", "pi-credentials");
  mkdirSync(agent, { recursive: true });
  mkdirSync(join(store, "auth-profiles"), { recursive: true });
  writeFileSync(join(store, "auth.json"), "{}");
  return { root, home, agent, store };
}

const posture = (f, environment, agent = noAgentProtection) => Effect.runSync(credentialPosture(f.home, f.agent, environment, agent));

test("with the executor, Pi's credential stores are host-only and runtime paths inside them are not writable", (t) => {
  const f = fixture(t);
  const executor = posture(f, { [MODEL_EXECUTOR_SOCKET]: "/private/executor.sock" });
  assert.equal(executor.mode, "executor");
  assert.ok(hostOnlyCredentials(executor).includes(f.store));
  assert.ok(hostOnlyCredentials(executor).includes(join(f.agent, "auth.json")));
  assert.equal(writableRuntimePath(executor, join(f.agent, "auth-profiles")), false);
  assert.equal(writableRuntimePath(executor, join(f.agent, "sessions")), true);
});

test("without the executor, Pi receives write grants to its own migrated login only", (t) => {
  const f = fixture(t);
  const authFile = join(f.agent, "auth.json");
  const sandbox = posture(f, {}, { ...noAgentProtection, authFiles: [authFile] });
  assert.equal(sandbox.mode, "sandbox");
  assert.deepEqual(sandbox.files, [grant("--allow-file", authFile), grant("--allow-file", join(f.store, "auth.json"))]);
  assert.deepEqual(sandbox.directories, [join(f.store, "auth-profiles")]);
  assert.deepEqual(hostOnlyCredentials(sandbox), []);
});

test("an executor session without a home directory falls back to sandbox mode", (t) => {
  const f = fixture(t);
  rmSync(f.home, { recursive: true });
  assert.equal(posture(f, { [MODEL_EXECUTOR_SOCKET]: "/private/executor.sock" }).mode, "sandbox");
});

test("in executor mode no grant may reach the credential store", (t) => {
  const f = fixture(t);
  const executor = posture(f, { [MODEL_EXECUTOR_SOCKET]: "/private/executor.sock" });
  const cwd = join(f.root, "project");
  mkdirSync(cwd);
  const check = (plan) => Effect.runSync(assertCredentialPosture(executor, plan, cwd, f.home, {}, {}));
  assert.doesNotThrow(() => check(grantPlan([grant("--read", cwd)])));
  assert.throws(() => check(grantPlan([grant("--read", f.home)])), /Pi credential store overlaps/);
  assert.doesNotThrow(() => Effect.runSync(assertCredentialPosture(posture(f, {}), grantPlan([grant("--read", f.home)]), cwd, f.home, {}, {})));
});
