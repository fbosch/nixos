import { afterEach, test } from "node:test";
import assert from "node:assert/strict";
import { spawnSync } from "node:child_process";
import { appendFileSync, chmodSync, existsSync, mkdirSync, mkdtempSync, readFileSync, rmSync, statSync, symlinkSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { fileURLToPath } from "node:url";
import { watchNonoDiagnostics } from "../scripts/nono-diagnostics-extension.mjs";
import { withNonoDiagnostics } from "../scripts/nono-diagnostics.mjs";
import { runWithCredentialProxy } from "../scripts/credential-proxy.mjs";

const roots = [];
afterEach(() => {
  for (const root of roots.splice(0)) rmSync(root, { recursive: true, force: true });
});

for (const { hasUI, native } of [{ hasUI: true }, { hasUI: false }, { hasUI: true, native: true }]) {
  test(`Nono tracing reaches ${hasUI ? "the prompt UI" : "headless stderr"} without raw terminal output${native ? " through native confinement" : ""}`, {
    skip: native && !process.env.NONO_PROXY_TEST_BINARY,
  }, () => {
    const root = mkdtempSync(join(tmpdir(), "pi-nono-diagnostics-test-"));
    roots.push(root);
    const home = join(root, "home");
    const cwd = join(root, "work");
    const agent = join(home, ".pi", "agent");
    for (const path of [cwd, agent, join(home, ".config"), join(home, ".local", "state")]) mkdirSync(path, { recursive: true });
    const profile = join(root, "profile.json");
    writeFileSync(profile, JSON.stringify({ filesystem: { allow: [cwd], read: ["/nix/store"] }, network: { block: true }, credential_capture: {} }));
    const observed = join(root, "observed.json");
    const nono = join(root, "nono");
    writeFileSync(nono, `#!${process.execPath}
import { appendFileSync, statSync, writeFileSync } from "node:fs";
import { spawn } from "node:child_process";
const args = process.argv.slice(2);
const log = args.includes("--log-file") ? args[args.indexOf("--log-file") + 1] : undefined;
writeFileSync(${JSON.stringify(observed)}, JSON.stringify({ log, mode: log ? statSync(log).mode & 0o777 : null }));
const emit = message => log ? appendFileSync(log, message) : process.stderr.write(message);
emit("2026-10-31T11:30:04Z WARN A synthetic startup warning\\n");
const native = ${JSON.stringify(native ? process.env.NONO_PROXY_TEST_BINARY : null)};
const command = native ? [native, ...args] : args.slice(args.indexOf("--") + 1);
const child = spawn(command[0], command.slice(1), { stdio: ["inherit", "pipe", "inherit"] });
let emitted = false;
child.stdout.on("data", chunk => {
  process.stdout.write(chunk);
  if (!emitted && chunk.toString().includes("READY")) {
    emitted = true;
    const warning = "2026-10-31T11:30:04Z WARN tls_intercept: Credential loading error: failed to wait for credential capture command: No child processes (os error 10) secret=synthetic-diagnostic-secret\\u001b[2J\\n";
    emit(warning); emit(warning);
  }
});
child.once("exit", status => process.exit(status ?? 1));
`, { mode: 0o700 });
    const pi = join(cwd, "pi");
    writeFileSync(pi, `#!${process.execPath}
const handlers = new Map();
const args = process.argv.slice(2);
let finish;
const done = new Promise(resolve => { finish = resolve; });
let notices = 0;
const context = { hasUI: ${hasUI}, mode: ${JSON.stringify(hasUI ? "tui" : "print")}, ui: { notify(message, level) {
  console.log(JSON.stringify({ notice: message, level }));
  if (++notices === 2) finish();
} } };
if (args.includes("--extension")) {
  const { default: extension } = await import(args[args.indexOf("--extension") + 1]);
  extension({ on(name, handler) { handlers.set(name, handler); } });
  await handlers.get("session_start")?.({}, context);
}
console.log("READY");
const timer = setTimeout(finish, 300);
await done;
clearTimeout(timer);
await handlers.get("session_shutdown")?.({}, context);
process.stderr.write("PI_STDERR_MARKER\\n");
`, { mode: 0o700 });
    const launcher = fileURLToPath(new URL("../scripts/launcher.mjs", import.meta.url));
    const result = spawnSync(process.execPath, [launcher, nono, pi, profile, "/missing-direnv", process.env.ENV_TEST_BINARY ?? "/usr/bin/env", ...(hasUI ? [] : ["--print"])], {
      cwd,
      env: { HOME: home, PI_NONO_DIAGNOSTICS: "1", PATH: process.env.PATH, TMPDIR: cwd, XDG_RUNTIME_DIR: cwd, XDG_STATE_HOME: join(home, ".local", "state"), PI_CODING_AGENT_DIR: agent },
      encoding: "utf8", timeout: 10000,
    });
    assert.ifError(result.error);
    assert.equal(result.status, 0, result.stderr);
    assert.doesNotMatch(result.stderr + result.stdout, /Credential loading error:|synthetic-diagnostic-secret|\u001b\[2J/);
    assert.match(result.stderr, /PI_STDERR_MARKER/);
    const notices = hasUI ? result.stdout.split("\n").filter(line => line.startsWith("{\"notice\":")).map(line => JSON.parse(line)) : [];
    if (hasUI) assert.deepEqual(notices, [
      { notice: "Nono reported a warning.", level: "warning" },
      { notice: "Nono could not wait for the credential capture command.", level: "warning" },
    ]);
    else assert.match(result.stderr, /Nono could not wait for the credential capture command\./);
    const actual = JSON.parse(readFileSync(observed, "utf8"));
    assert.equal(actual.mode, 0o600);
    assert.equal(existsSync(actual.log), false);
  });
}

test("the watcher waits for complete records and stops notifying after disposal", async () => {
  await withNonoDiagnostics({}, async environment => {
    const path = environment.PI_NONO_DIAGNOSTICS_FILE;
    const messages = [];
    let received;
    const next = new Promise(resolve => { received = resolve; });
    const dispose = watchNonoDiagnostics(path, (message, level) => { messages.push({ message, level }); received(); });
    try {
      appendFileSync(path, "WARN Credential loading error");
      assert.deepEqual(messages, []);
      appendFileSync(path, ": fixture-secret\n");
      await next;
      assert.deepEqual(messages, [{ message: "Nono could not load credentials.", level: "warning" }]);
    } finally {
      dispose();
    }
    appendFileSync(path, "ERROR another fixture-secret\n");
    await new Promise(resolve => setImmediate(resolve));
    assert.equal(messages.length, 1);
  });
});

test("diagnostics reject symlinks and group-readable files", async () => {
  await withNonoDiagnostics({}, async environment => {
    const path = environment.PI_NONO_DIAGNOSTICS_FILE;
    const link = path + ".link";
    symlinkSync(path, link);
    assert.throws(() => watchNonoDiagnostics(link, () => {}));
    chmodSync(path, 0o640);
    assert.throws(() => watchNonoDiagnostics(path, () => {}), /owner-only/);
  });
});

test("large logs are read from a bounded tail without exposing raw text", async () => {
  await withNonoDiagnostics({}, async environment => {
    const path = environment.PI_NONO_DIAGNOSTICS_FILE;
    writeFileSync(path, "WARN " + "synthetic-secret".repeat(10000) + "\nERROR synthetic-secret\n");
    const messages = [];
    const dispose = watchNonoDiagnostics(path, (message, level) => messages.push({ message, level }));
    dispose();
    assert.deepEqual(messages, [{ message: "Nono reported an error.", level: "error" }]);
  });
});

test("private diagnostics are cleaned up when launching fails", async () => {
  let path;
  await assert.rejects(withNonoDiagnostics({}, async environment => {
    path = environment.PI_NONO_DIAGNOSTICS_FILE;
    assert.equal(statSync(path).mode & 0o777, 0o600);
    assert.equal(statSync(join(path, "..")).mode & 0o777, 0o700);
    throw new Error("fixture launch failure");
  }), /fixture launch failure/);
  assert.equal(existsSync(path), false);
});

test("malformed proxy profiles fail before capture without echoing profile contents", async () => {
  const root = mkdtempSync(join(tmpdir(), "pi-proxy-invalid-profile-"));
  roots.push(root);
  const profile = join(root, "profile.json");
  writeFileSync(profile, "{synthetic-profile-secret");
  await assert.rejects(
    runWithCredentialProxy(process.execPath, profile, [process.execPath, "-e", ""], {}),
    { message: "Nix nono profile is not valid JSON" },
  );
});
