import assert from "node:assert/strict";
import { createHash } from "node:crypto";
import { mkdirSync, mkdtempSync, readFileSync, realpathSync, rmSync, symlinkSync, writeFileSync } from "node:fs";
import { join } from "node:path";
import { afterEach, test } from "node:test";
import { launchArguments } from "../scripts/launcher.mjs";
import { devenvRuntime, serviceSocketArguments, withSessionServiceEnvironment } from "../scripts/service-ipc.mjs";

const roots = [];
const envBinary = process.env.ENV_TEST_BINARY || "/usr/bin/env";
const base = JSON.parse(readFileSync(new URL("../scripts/profile.json", import.meta.url), "utf8"));
function fixture() {
  const root = realpathSync(mkdtempSync(join(process.cwd(), ".pi-service-")));
  roots.push(root);
  const home = join(root, "home");
  const project = join(root, "project");
  const environment = { HOME: home, XDG_RUNTIME_DIR: join(root, "runtime") };
  for (const path of [home, project, environment.XDG_RUNTIME_DIR]) mkdirSync(path, { recursive: true });
  writeFileSync(join(project, "devenv.nix"), "{}");
  const candidate = join(root, "candidate.json");
  writeFileSync(candidate, JSON.stringify({ ...base, linux: { af_unix_mediation: "pathname", sandbox_policy: "landlock" } }));
  return { root, home, project, environment, candidate };
}
afterEach(() => { for (const root of roots.splice(0)) rmSync(root, { recursive: true, force: true }); });
const values = (args, flag) => args.flatMap((part, index) => part === flag ? [args[index + 1]] : []);

test("devenv 2.4 runtime follows the selected canonical dotfile, including profiles, not DEVENV_RUNTIME or TMPDIR", () => {
  const f = fixture();
  const expected = dotfile => join(f.environment.XDG_RUNTIME_DIR, `devenv-${createHash("sha256").update(dotfile).digest("hex").slice(0, 7)}`);
  assert.equal(devenvRuntime(f.project, f.home, { ...f.environment, DEVENV_RUNTIME: "/unrelated", TMPDIR: "/different" }), expected(join(f.project, ".devenv")));
  const profile = join(f.project, ".devenv", "profile-hash");
  mkdirSync(profile, { recursive: true });
  const alias = join(f.root, "alias");
  symlinkSync(f.project, alias);
  const nested = join(f.project, "src");
  mkdirSync(nested);
  assert.equal(devenvRuntime(nested, f.home, { ...f.environment, DEVENV_ROOT: alias, DEVENV_DOTFILE: join(alias, ".devenv", "profile-hash") }), expected(profile));
  assert.ok(devenvRuntime(f.project, f.home, {}).startsWith("/tmp/devenv-"));
});

test("candidate grants the project runtime and direct service directories without exposing the desktop runtime root", () => {
  const f = fixture();
  const runtime = devenvRuntime(f.project, f.home, f.environment);
  mkdirSync(join(runtime, "postgres"), { recursive: true, mode: 0o700 });
  const agent = join(f.home, ".pi", "agent");
  mkdirSync(agent, { recursive: true });
  const args = launchArguments(f.project, agent, f.home, f.environment, f.candidate, process.execPath, envBinary, "linux");
  assert.ok(values(args, "--allow").includes(runtime));
  assert.ok(!values(args, "--allow").includes(f.environment.XDG_RUNTIME_DIR));
  assert.deepEqual(values(args, "--allow-unix-socket-dir-bind").sort(), [runtime, join(runtime, "postgres"), join(runtime, "processes")].sort());
  assert.deepEqual(values(args, "--allow-unix-socket-subtree-bind"), []);
  assert.deepEqual(values(args, "--allow-unix-socket-subtree"), []);
});

test("candidate rejects project runtime aliases instead of granting their targets", () => {
  const f = fixture();
  const runtime = devenvRuntime(f.project, f.home, f.environment);
  const target = join(f.root, "unrelated");
  mkdirSync(target, { mode: 0o700 });
  symlinkSync(target, runtime);
  assert.throws(() => serviceSocketArguments(f.project, f.home, f.environment, true), /private, user-owned directory without symlinks/);
});

test("each launch isolates browser daemons and uses local LSPs instead of unrestricted warm peers", async () => {
  const f = fixture();
  const previous = { AGENT_BROWSER_SOCKET_DIR: "/host/browser", AGENT_BROWSER_NAMESPACE: "host", AGENT_BROWSER_CDP: "9222", PI_LENS_WARM_ATTACH: "1" };
  let first;
  await withSessionServiceEnvironment(previous, f.home, async environment => {
    first = environment.AGENT_BROWSER_SOCKET_DIR;
    assert.equal(environment.PI_LENS_WARM_ATTACH, "0");
    assert.equal(environment.AGENT_BROWSER_NAMESPACE, undefined);
    assert.equal(environment.AGENT_BROWSER_CDP, undefined);
    const args = serviceSocketArguments(f.home, f.home, environment, true);
    assert.deepEqual(args, ["--allow", first, "--allow-unix-socket-dir-bind", first]);
  });
  assert.throws(() => realpathSync(first), /ENOENT/);
  await withSessionServiceEnvironment(previous, f.home, environment => assert.notEqual(environment.AGENT_BROWSER_SOCKET_DIR, first));
  assert.equal(previous.PI_LENS_WARM_ATTACH, "1", "do not mutate the caller's environment");
});
