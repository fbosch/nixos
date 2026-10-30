import assert from "node:assert/strict";
import { execFile, spawn } from "node:child_process";
import { createInterface } from "node:readline";
import { once } from "node:events";
import { mkdirSync, mkdtempSync, readFileSync, realpathSync, rmSync, symlinkSync, writeFileSync } from "node:fs";
import { createServer } from "node:net";
import { join, relative } from "node:path";
import { test } from "node:test";
import { fileURLToPath } from "node:url";
import { promisify } from "node:util";

const execute = promisify(execFile);
const launcher = fileURLToPath(new URL("../scripts/launcher.mjs", import.meta.url));
const probe = readFileSync(new URL("./fixtures/ipc-workflows-probe.mjs", import.meta.url), "utf8");
const base = JSON.parse(readFileSync(new URL("../scripts/profile.json", import.meta.url), "utf8"));

for (const { browser, fsmonitor } of [{ browser: false, fsmonitor: false }, { browser: false, fsmonitor: true }, { browser: true, fsmonitor: false }]) {
  const editor = !browser && !fsmonitor && Boolean(process.env.NVIM_TEST_BINARY);
  test(`actual launcher confines reporting${fsmonitor ? " and starts Git fsmonitor" : browser ? " and starts its own Lightpanda browser" : " and rejects raw-service aliases"}`, {
    skip: !process.env.NONO_TEST_BINARY || fsmonitor && !(process.platform === "darwin" && process.env.GIT_TEST_BINARY) || browser && !(process.env.AGENT_BROWSER_TEST_BINARY && process.env.LIGHTPANDA_TEST_BINARY),
    timeout: 45000,
  }, async () => {
    const root = realpathSync(mkdtempSync(join(process.cwd(), ".pi-e2e-")));
    const home = join(root, "h");
    const work = join(root, "w");
    const upstream = join(home, "host", "herdr.sock");
    const received = [];
    const connections = new Set();
    const server = createServer(socket => {
      connections.add(socket);
      socket.on("close", () => connections.delete(socket));
      let data = "";
      socket.on("data", chunk => {
        data += chunk.toString();
        if (!data.includes("\n")) return;
        received.push(JSON.parse(data));
        socket.end('{"ok":true}\n');
      });
    });
    let nvim;
    let nvimExited;
    let editorIdentity;
    let nvimOutput;
    const nativeEndpoints = [];
    const git = fsmonitor ? process.env.GIT_TEST_BINARY : undefined;
    let gitInitialized = false;
    try {
      const environment = {
        PATH: process.env.PATH, HOME: home, NO_COLOR: "1",
        HERDR_ENV: "1", HERDR_PANE_ID: "wFixture:p1", HERDR_SOCKET_PATH: upstream,
        PI_CODING_AGENT_DIR: join(home, ".pi", "agent"),
        XDG_CONFIG_HOME: join(root, "config"), XDG_STATE_HOME: join(root, "state"),
        XDG_CACHE_HOME: join(root, "cache"), XDG_DATA_HOME: join(root, "data"),
        XDG_RUNTIME_DIR: join(root, "runtime"), TMPDIR: join(root, "tmp"),
      };
      for (const path of [work, join(home, "host"), ...Object.entries(environment).filter(([name]) => /^(XDG_|TMPDIR|PI_CODING_AGENT_DIR)/.test(name)).map(([, value]) => value)]) mkdirSync(path, { recursive: true });
      writeFileSync(join(work, "devenv.nix"), "{}");
      if (git) {
        await execute(git, ["-c", "init.templateDir=", "init", "--quiet", work], { env: environment });
        gitInitialized = true;
      }
      server.listen(upstream);
      await once(server, "listening");
      const alias = join(work, "host-alias.sock");
      symlinkSync(upstream, alias);
      const directoryAlias = join(work, "host-alias");
      symlinkSync(join(home, "host"), directoryAlias);
      if (editor) {
        const sources = ["../scripts/pi-ask.lua", "./pi-ask-host.lua"].map(path => fileURLToPath(new URL(path, import.meta.url)));
        const stored = await Promise.all(sources.map(path => execute("nix-store", ["--add", path], { encoding: "utf8" })));
        const [helper, harness] = stored.map(result => result.stdout.trim());
        nvim = spawn(process.env.NVIM_TEST_BINARY, ["--headless", "-u", "NONE", "-i", "NONE", "-l", harness], {
          cwd: work,
          env: { ...environment, PI_ASK_TEST_HOST: helper, PI_ASK_TEST_CWD: work, PI_ASK_TEST_NATIVE: join(home, "host", "nvim.sock") },
          stdio: ["ignore", "pipe", "pipe"],
        });
        nvimExited = once(nvim, "exit");
        let stderr = "";
        nvim.stderr.on("data", chunk => { stderr += chunk.toString(); });
        nvimOutput = createInterface({ input: nvim.stdout });
        editorIdentity = await new Promise((resolve, reject) => {
          const timer = setTimeout(() => reject(new Error(`Neovim did not start: ${stderr}`)), 5000);
          nvimOutput.once("line", line => {
            clearTimeout(timer);
            try { resolve(JSON.parse(line)); } catch (error) { reject(error); }
          });
          nvim.once("error", reject);
          nvim.once("exit", () => { clearTimeout(timer); reject(new Error(`Neovim exited: ${stderr}`)); });
        });
        environment.PI_NVIM_ASK_SOCKET = editorIdentity.socketPath;
        environment.PI_NVIM_LAUNCH_ID = "0123456789abcdef0123456789abcdef";
        const nativeAlias = join(work, "native-alias.sock");
        symlinkSync(editorIdentity.native, nativeAlias);
        nativeEndpoints.push(editorIdentity.native, editorIdentity.alternate, nativeAlias, join(directoryAlias, "nvim.sock"), relative(work, editorIdentity.native));
        const native = await execute(process.env.NVIM_TEST_BINARY, ["--server", editorIdentity.native, "--remote-expr", "getpid()"], { encoding: "utf8" });
        assert.ok(Number(native.stdout.trim()) > 0, "the native RPC fixture must work outside Nono");
      }
      const program = join(work, "probe.mjs");
      writeFileSync(program, probe);
      const profile = join(root, "profile.json");
      writeFileSync(profile, JSON.stringify({
        ...base,
        linux: { af_unix_mediation: "pathname", sandbox_policy: "landlock" },
        network: { ...base.network, credentials: ["fixture"], custom_credentials: {
          fixture: { upstream: "https://example.invalid", credential_key: "cmd://fixture", env_var: "FIXTURE_TOKEN" },
        } },
        credential_capture: { fixture: { command: [process.execPath, "-e", 'console.log("synthetic-credential")'] } },
      }));
      // Run the actual launcher and Nono. The shim omits only Keychain CA installation,
      // which is unrelated to IPC and must not mutate the developer's trust store in tests.
      const nono = join(work, "nono-test.mjs");
      writeFileSync(nono, `#!${process.execPath}\nimport { spawnSync } from "node:child_process";\nconst args=process.argv.slice(2).filter(arg => arg !== "--trust-proxy-ca");\nconst child=spawnSync(${JSON.stringify(process.env.NONO_TEST_BINARY)},args,{stdio:"inherit"});\nif(child.error) throw child.error;\nprocess.exit(child.status??1);\n`, { mode: 0o700 });
      const child = await execute(process.execPath, [launcher, nono, process.execPath, profile, "/missing-direnv", process.env.ENV_TEST_BINARY || "/usr/bin/env", program, JSON.stringify({
        upstream, aliases: [alias, join(directoryAlias, "herdr.sock"), relative(work, upstream)],
        ...(git ? { git } : {}),
        ...(editor ? { editor: editorIdentity, nativeEndpoints } : {}),
        ...(browser ? { browser: process.env.AGENT_BROWSER_TEST_BINARY, lightpanda: process.env.LIGHTPANDA_TEST_BINARY } : {}),
      })], { cwd: work, env: environment, encoding: "utf8", timeout: 35000, killSignal: "SIGKILL" });
      assert.match(child.stdout, /IPC workflows verified/);
      if (editor) assert.equal((await nvimExited)[0], 0, "the editor must acknowledge, reconnect, and close cleanly");
      assert.ok(received.length >= 3, "the lifecycle report and host-side cleanup must reach the service");
      assert.ok(received.every(value => ["pane.report_agent", "pane.report_metadata", "pane.release_agent"].includes(value.method)));
      assert.ok(received.every(value => value.params.pane_id === "wFixture:p1" && value.params.resume_argv === undefined));
    } finally {
      if (gitInitialized) {
        try {
          await execute(git, ["-C", work, "fsmonitor--daemon", "stop"], { env: { PATH: process.env.PATH, HOME: home, GIT_CONFIG_NOSYSTEM: "1", GIT_CONFIG_GLOBAL: "/dev/null" } });
        } catch (error) {
          if (error.code !== 128 || !/fsmonitor--daemon is not running/.test(error.stderr ?? "")) throw error;
        }
      }
      if (nvim && nvim.exitCode === null && nvim.signalCode === null) nvim.kill();
      if (nvimExited) await nvimExited;
      nvimOutput?.close();
      for (const socket of connections) socket.destroy();
      await new Promise(resolve => server.close(resolve));
      rmSync(root, { recursive: true, force: true });
    }
  });
}
