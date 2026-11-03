import * as Effect from "effect/Effect";
import assert from "node:assert/strict";
import { spawnSync } from "node:child_process";
import { linkSync, mkdirSync, mkdtempSync, readFileSync, realpathSync, rmSync, symlinkSync, writeFileSync } from "node:fs";
import { join } from "node:path";
import { afterEach, test } from "node:test";
import { once } from "node:events";
import { createServer } from "node:net";
import { agentProtection, prepareAgentRuntime } from "../scripts/protection/agent.mts";
import { protectedShellProfile } from "../scripts/protection/shell.mts";
import { withScopedSync } from "./fixtures/scoped.mjs";

const roots = [];
function fixture() {
  const root = realpathSync(mkdtempSync(join(process.platform === "darwin" ? "/tmp" : process.cwd(), ".pi-controls-")));
  roots.push(root);
  const home = join(root, "home");
  const agent = join(home, "dotfiles", ".pi", "agent");
  const defaultAgent = join(home, ".pi", "agent");
  const work = join(home, "project");
  const temporary = join(root, "tmp");
  for (const path of [agent, defaultAgent, work, temporary]) mkdirSync(path, { recursive: true });
  mkdirSync(join(work, ".git"));
  prepareAgentRuntime(agent);
  for (const name of ["extensions", "lib"]) mkdirSync(join(agent, name));
  writeFileSync(join(agent, "settings.json"), JSON.stringify({
    references: { dotfiles: { path: join(home, "dotfiles"), description: "Approved paired repository" } },
    extensions: ["-builtin:mcp", "./lib/approved.mjs"],
    packages: [], enableInstallTelemetry: false,
  }));
  writeFileSync(join(agent, "auth.json"), "{}");
  writeFileSync(join(agent, "lib", "approved.mjs"), 'export default pi => { pi.registerCommand("approved-lockdown-proof", { description: "Local fixture", handler: async () => {} }); };\n');
  writeFileSync(join(agent, "extensions", "existing.mjs"), "export default () => {};\n");
  symlinkSync(join(agent, "settings.json"), join(defaultAgent, "settings.json"));
  symlinkSync(join(agent, "extensions"), join(defaultAgent, "extensions"));
  return { root, home, agent, defaultAgent, work, temporary };
}
afterEach(() => { for (const root of roots.splice(0)) rmSync(root, { recursive: true, force: true }); });

test("control paths include default and configured settings and extension targets", () => {
  const f = fixture();
  const policy = Effect.runSync(agentProtection(f.home, f.agent));
  for (const base of [f.agent, f.defaultAgent]) {
    for (const name of ["settings.json", "extensions", "lib", "npm", "mcp.json"]) {
      assert.ok(policy.protectedPaths.includes(join(base, name)), `${base}/${name}`);
    }
  }
  assert.deepEqual(policy.authFiles, [join(f.agent, "auth.json")]);
  assert.deepEqual(new Set(policy.runtimePaths), new Set(
    ["sessions", "cache", "session-history", "tasks", "auth-profiles", "fff"].map(name => join(f.agent, name)),
  ));
});

test("FFF fallback databases have a prepared writable data directory", () => {
  const f = fixture();
  const data = join(f.agent, "fff");
  const policy = Effect.runSync(agentProtection(f.home, f.agent));
  assert.ok(policy.runtimePaths.includes(data));
  assert.ok(policy.protectedPaths.includes(join(f.agent, "settings.json")));
  for (const name of ["frecency", "history"]) {
    mkdirSync(join(data, name));
    writeFileSync(join(data, name, "fixture.mdb"), "runtime data");
  }
});
test("linked extension dependencies remain protected outside the agent directory", () => {
  const f = fixture();
  const external = join(f.home, "external-library");
  mkdirSync(external);
  writeFileSync(join(external, "index.mjs"), "export default {};\n");
  symlinkSync(external, join(f.agent, "extensions", "external"));
  assert.ok(Effect.runSync(agentProtection(f.home, f.agent)).protectedPaths.includes(external));
});

test("Linux rejects executable resources beneath an unsplittable writable cache grant", () => {
  const f = fixture();
  const cache = join(f.home, ".cache", "plugin");
  mkdirSync(cache, { recursive: true });
  writeFileSync(join(cache, "index.mjs"), "export default {};");
  symlinkSync(cache, join(f.agent, "extensions", "cached"));
  assert.throws(() => Effect.runSync(agentProtection(f.home, f.agent, {}, {}, "linux")), /writable profile or default-group grant/);
});
test("dangling Stow targets are protected before they are created", () => {
  const f = fixture();
  const target = join(f.home, "future-library", "extension.mjs");
  symlinkSync(target, join(f.agent, "extensions", "future.mjs"));
  assert.ok(Effect.runSync(agentProtection(f.home, f.agent)).protectedPaths.includes(target));
});
test("invalid directory traversal in an extension link fails closed", () => {
  const f = fixture();
  const file = join(f.home, "not-a-directory");
  writeFileSync(file, "fixture");
  symlinkSync(`${file}/../future.mjs`, join(f.agent, "extensions", "invalid.mjs"));
  assert.throws(() => Effect.runSync(agentProtection(f.home, f.agent)), /Not a Pi control directory/);
});

test("runtime directories cannot alias protected extension code", () => {
  const f = fixture();
  rmSync(join(f.agent, "cache"), { recursive: true });
  symlinkSync(join(f.agent, "extensions"), join(f.agent, "cache"));
  assert.throws(() => Effect.runSync(agentProtection(f.home, f.agent)), /runtime state overlaps a protected control path/);
});

test("hard links cannot leave writable aliases to protected code", () => {
  const f = fixture();
  linkSync(join(f.agent, "extensions", "existing.mjs"), join(f.work, "alias.mjs"));
  assert.throws(() => Effect.runSync(agentProtection(f.home, f.agent)), /not hard-linked/);
});

test("auth state cannot select a control file through a symlink", () => {
  const f = fixture();
  rmSync(join(f.agent, "auth.json"));
  symlinkSync(join(f.agent, "settings.json"), join(f.agent, "auth.json"));
  assert.throws(() => Effect.runSync(agentProtection(f.home, f.agent)), /auth state must be a regular file/);
});

test("a Stow-linked default auth file shares the configured agent's auth file", () => {
  const f = fixture();
  symlinkSync(join(f.agent, "auth.json"), join(f.defaultAgent, "auth.json"));
  const policy = Effect.runSync(agentProtection(f.home, f.agent));
  assert.deepEqual(policy.authFiles, [join(f.agent, "auth.json")]);
  assert.ok(policy.protectedPaths.includes(join(f.defaultAgent, "auth.json")), "the link itself stays host-owned");
});

test("a default auth link may not select any other file", () => {
  const f = fixture();
  writeFileSync(join(f.home, "elsewhere.json"), "{}");
  for (const target of [join(f.agent, "settings.json"), join(f.home, "elsewhere.json"), join(f.agent, "missing.json")]) {
    rmSync(join(f.defaultAgent, "auth.json"), { force: true });
    symlinkSync(target, join(f.defaultAgent, "auth.json"));
    assert.throws(() => Effect.runSync(agentProtection(f.home, f.agent)), /auth state must be a regular file/, target);
  }
});

test("fresh native sandbox denies control writes and loads an approved Pi extension", {
  skip: !["linux", "darwin"].includes(process.platform) || !process.env.NONO_TEST_BINARY || !process.env.PI_RAW_TEST_BINARY,
  timeout: 60000,
}, async t => {
  const f = fixture();
  const fish = join(f.home, "dotfiles", ".config", "fish");
  mkdirSync(fish, { recursive: true });
  mkdirSync(join(f.home, ".config", "fish"), { recursive: true });
  writeFileSync(join(fish, "config.fish"), "# synthetic shell config\n");
  symlinkSync(join(fish, "config.fish"), join(f.home, ".config", "fish", "config.fish"));
  mkdirSync(join(f.home, ".claude"));
  writeFileSync(join(f.home, ".claude", ".credentials.json"), "synthetic OAuth fixture");
  const agentSocket = join(f.root, "ssh-agent.sock");
  const server = createServer(connection => connection.end());
  server.listen(agentSocket);
  await once(server, "listening");
  t.after(() => new Promise(resolve => server.close(resolve)));
  const { launchArguments } = await import("../scripts/launch/plan.mts");
  const { prepareSandboxRuntime } = await import("../scripts/launch/runtime.mts");
  prepareSandboxRuntime(f.home);
  const profile = JSON.parse(readFileSync(new URL("../scripts/profile.json", import.meta.url), "utf8"));
  // Short macOS socket fixtures use /tmp; keep synthetic HOME outside explicit temporary read grants.
  profile.filesystem.read = profile.filesystem.read.filter(path => path !== "/tmp");
  profile.network = { block: true };
  profile.linux.af_unix_mediation = "pathname";
  const profilePath = join(f.root, "offline.json");
  writeFileSync(profilePath, JSON.stringify(profile));
  const environment = {
    HOME: f.home, PATH: process.env.PATH, TMPDIR: f.temporary,
    XDG_STATE_HOME: join(f.root, "state"), XDG_CACHE_HOME: join(f.home, ".cache"),
    PI_CODING_AGENT_DIR: f.agent, PI_SKIP_VERSION_CHECK: "1", PI_TELEMETRY: "0", NO_COLOR: "1",
    TEST_AGENT_SOCKET: agentSocket,
    CURL_TEST_BINARY: process.env.CURL_TEST_BINARY, BASH_TEST_BINARY: process.env.BASH_TEST_BINARY,
    CAT_TEST_BINARY: process.env.CAT_TEST_BINARY, SSH_ADD_TEST_BINARY: process.env.SSH_ADD_TEST_BINARY,
  };
  const args = launchArguments(f.work, f.agent, f.home, environment, profilePath, process.execPath, process.env.ENV_TEST_BINARY);
  const probe = `
    const assert = require("node:assert/strict");
    const fs = require("node:fs");
    const path = require("node:path");
    const { spawnSync } = require("node:child_process");
    const [agent, defaultAgent, rawPi] = process.argv.slice(1);
    const denied = e => ["EACCES", "EPERM"].includes(e.code);
    for (const base of [agent, defaultAgent]) {
      assert.throws(() => fs.appendFileSync(path.join(base, "settings.json"), "p"), denied);
      assert.throws(() => fs.mkdirSync(path.join(base, "extensions", "planted")), denied);
      assert.throws(() => fs.appendFileSync(path.join(base, "extensions", "existing.mjs"), "p"), denied);
    }
    fs.writeFileSync(path.join(agent, "auth.json"), "{}");
    assert.equal(fs.readFileSync(path.join(agent, "auth.json"), "utf8"), "{}");
    fs.writeFileSync(path.join(agent, "sessions", "fixture-session"), "session data");
    fs.writeFileSync(path.join(agent, "cache", "fixture-data"), "cache data");
    for (const name of ["frecency", "history"]) {
      const directory = path.join(agent, "fff", name);
      fs.mkdirSync(directory);
      fs.writeFileSync(path.join(directory, "fixture.mdb"), "runtime data");
      assert.equal(fs.readFileSync(path.join(directory, "fixture.mdb"), "utf8"), "runtime data");
    }
    assert.equal(process.env.JITI_FS_CACHE, "false");
    const run = (binary, args, extra = {}) => spawnSync(binary, args, {
      env: {...process.env, ...extra}, encoding:"utf8", timeout:7000,
    });
    const report = {settingsWrites:"denied", extensionWrites:"denied"};
    const checkDenied = (name, result) => {
      assert.ifError(result.error);
      assert.notEqual(result.status, 0, name);
      assert.match(result.stderr, /Permission denied|Operation not permitted|Read-only file system/, name);
      report[name] = {status:result.status, denied:true};
    };
    const curl = run(process.env.CURL_TEST_BINARY, ["--noproxy", "*", "-m5", "-o", "/dev/null", "-w", "%{http_code}", "https://ifconfig.me"]);
    assert.ifError(curl.error);
    assert.equal(curl.stdout, "000");
    assert.notEqual(curl.status, 0);
    report.directHttps = {status:curl.status, http:curl.stdout};
    checkDenied("directSsh", run(process.env.BASH_TEST_BINARY, ["-c", "exec 3<>/dev/tcp/140.82.121.4/22"]));
    checkDenied("claudeCredentials", run(process.env.CAT_TEST_BINARY, [path.join(process.env.HOME, ".claude", ".credentials.json")]));
    checkDenied("sshAgent", run(process.env.SSH_ADD_TEST_BINARY, ["-l"], {SSH_AUTH_SOCK:process.env.TEST_AGENT_SOCKET}));
    checkDenied("fishConfig", run(process.env.BASH_TEST_BINARY, ["-c", 'echo p >> "$HOME/.config/fish/config.fish"']));
    if (process.platform === "linux") {
      checkDenied("corePattern", run(process.env.BASH_TEST_BINARY, ["-c", "echo p >> /proc/sys/kernel/core_pattern"]));
      const proc = run(process.env.CAT_TEST_BINARY, ["/proc/1/cmdline"]);
      report.otherProcessCmdline = {status:proc.status, denied:proc.status !== 0};
      const comm = run(process.env.CAT_TEST_BINARY, ["/proc/1/comm"]);
      report.otherProcessComm = {status:comm.status, denied:comm.status !== 0};
      checkDenied("otherProcessEnviron", run(process.env.CAT_TEST_BINARY, ["/proc/1/environ"]));
      const self = run(process.env.CAT_TEST_BINARY, ["/proc/self/cmdline"]);
      assert.equal(self.status, 0, self.stderr);
      report.selfCmdline = {status:self.status, readable:true};
    }
    // DNS is unavailable in a Nix build; check TCP errno separately so curl's 000 cannot be a false pass.
    Promise.all([22, 80, 443].map(port => new Promise(resolve => {
      const socket = require("node:net").connect({host:process.platform === "darwin" ? "192.0.2.1" : "127.0.0.1", port});
      const finish = code => { socket.destroy(); resolve({port, code}); };
      socket.once("connect", () => finish("connected"));
      socket.once("error", error => finish(error.code));
      socket.setTimeout(3000, () => finish("timeout"));
    }))).then(results => {
      for (const result of results) assert.ok(["EACCES", "EPERM"].includes(result.code), JSON.stringify(result));
      report.directTcp = results;
      console.log("DENIAL_PROBE_REPORT " + JSON.stringify(report));
    }).catch(error => { console.error(error); process.exitCode = 1; });
    const pi = spawnSync(rawPi, ["--mode", "rpc", "--no-session"], {
      input: JSON.stringify({id:"proof",type:"get_commands"}) + "\\n",
      env: process.env, encoding: "utf8", timeout: 20000,
    });
    assert.ifError(pi.error);
    assert.equal(pi.status, 0, pi.stderr);
    assert.match(pi.stdout, /approved-lockdown-proof/, pi.stdout + pi.stderr);
    console.log("settings and extension writes denied; approved extension loaded; runtime data writable");
  `;
  const controls = Effect.runSync(agentProtection(f.home, f.agent, environment, profile)).protectedPaths;
  withScopedSync(protectedShellProfile(profilePath, f.home, environment, process.platform, controls), selectedProfile => {
    const prepared = [...args];
    prepared[prepared.indexOf("--profile") + 1] = selectedProfile;
    const child = spawnSync(process.env.NONO_TEST_BINARY, [...prepared, "-e", probe, f.agent, f.defaultAgent, process.env.PI_RAW_TEST_BINARY], {
      cwd: f.work, env: environment, encoding: "utf8", timeout: 45000,
    });
    assert.ifError(child.error);
    assert.equal(child.status, 0, child.stdout + child.stderr);
    assert.match(child.stdout, /approved extension loaded/);
    const report = child.stdout.split("\n").find(line => line.startsWith("DENIAL_PROBE_REPORT "));
    assert.ok(report);
    t.diagnostic(report);
  });
});
