import assert from "node:assert/strict";
import { execFile, spawn } from "node:child_process";
import { once } from "node:events";
import { mkdirSync, mkdtempSync, realpathSync, rmSync } from "node:fs";
import { join } from "node:path";
import { createInterface } from "node:readline";
import { test } from "node:test";
import { fileURLToPath } from "node:url";
import { promisify } from "node:util";

const execute = promisify(execFile);
const path = relative => fileURLToPath(new URL(relative, import.meta.url));

test("raw editor launches use only the Ask broker and bypass sandbox prerequisites", {
  skip: !process.env.NVIM_TEST_BINARY, timeout: 20000,
}, async () => {
  const root = realpathSync(mkdtempSync("/tmp/pi-raw-ask-"));
  const home = join(root, "h");
  mkdirSync(home, { mode: 0o700 });
  const editor = spawn(process.env.NVIM_TEST_BINARY, ["--headless", "-u", "NONE", "-i", "NONE", "-l", path("./fixtures/neovim-host.lua")], {
    cwd: root, env: { HOME: home, PI_ASK_TEST_CWD: root }, stdio: ["ignore", "pipe", "pipe"],
  });
  const editorExited = once(editor, "exit");
  const output = createInterface({ input: editor.stdout });
  let errors = "";
  editor.stderr.on("data", chunk => { errors += chunk; });
  try {
    const ready = JSON.parse((await once(output, "line"))[0]);
    const child = await execute(process.execPath, [path("../scripts/launcher.mts"), "/missing/nono", process.execPath,
      "/missing/profile", "/missing/direnv", "/missing/env", "--no-sandbox", path("./fixtures/neovim-raw-probe.mjs")], {
      cwd: root, env: { HOME: home, PATH: process.env.PATH, PI_NVIM_SOCKET: ready.socketPath,
        PI_NVIM_LAUNCH_ID: "0123456789abcdef0123456789abcdef", PI_IPC_MANIFEST: "/missing/manifest", PI_MODEL_EXECUTOR_SOCKET: "/inherited/executor" },
      encoding: "utf8", timeout: 15000,
    });
    assert.match(child.stdout, /Raw editor broker verified/);
    assert.equal((await editorExited)[0], 0, errors);
  } finally {
    if (editor.exitCode === null && editor.signalCode === null) editor.kill();
    await editorExited;
    output.close();
    rmSync(root, { recursive: true, force: true });
  }
});
