import assert from "node:assert/strict";
import { once } from "node:events";
import { existsSync, mkdirSync, mkdtempSync, readFileSync, realpathSync, rmSync, writeFileSync } from "node:fs";
import { createConnection, createServer } from "node:net";
import { join } from "node:path";
import { afterEach, test } from "node:test";
import { createDesktopHandler, desktopAuthority, withDesktopBroker } from "../scripts/desktop-broker.mjs";
import { createMessageValidator, defaultCapabilities } from "../scripts/ipc-policy.mjs";
import { main, parseArguments } from "../scripts/pi-desktop.mjs";

const capability = defaultCapabilities.capabilities.desktop;
const created = [];
const servers = [];
afterEach(async () => {
  for (const server of servers.splice(0)) await new Promise(resolve => server.close(resolve));
  for (const path of created.splice(0)) rmSync(path, { recursive: true, force: true });
});

// Fixture tools record their arguments, environment and stdin, then behave like wl-copy and grim.
function tool(path, body) {
  writeFileSync(path, `#!${process.execPath}\nconst fs = require("node:fs");\n${body}\n`, { mode: 0o755 });
  return path;
}

async function fixture({ grimBody } = {}) {
  // Keep socket paths short and outside shared temporary-directory grants.
  const root = realpathSync(mkdtempSync(join(process.cwd(), ".pi-desk-")));
  created.push(root);
  const home = join(root, "home");
  const runtime = join(root, "run");
  for (const path of [home, runtime]) mkdirSync(path, { recursive: true });
  const record = join(root, "record.json");
  const display = createServer(socket => socket.destroy());
  servers.push(display);
  display.listen(join(runtime, "wl"));
  await once(display, "listening");
  const wlCopy = tool(join(root, "wl-copy"), `fs.writeFileSync(${JSON.stringify(record)}, JSON.stringify({ args: process.argv.slice(2), env: Object.keys(process.env).sort(), input: fs.readFileSync(0, "utf8") }));`);
  const grim = tool(join(root, "grim"), grimBody ?? `fs.writeFileSync(${JSON.stringify(record)}, JSON.stringify({ args: process.argv.slice(2) })); process.stdout.write(Buffer.from([0x89, 0x50, 0x4e, 0x47, 0, 255]));`);
  const inherited = { WAYLAND_DISPLAY: "wl", XDG_RUNTIME_DIR: runtime, PI_DESKTOP_WL_COPY: wlCopy, PI_DESKTOP_GRIM: grim, PI_DESKTOP_PATH: root };
  return { root, home, runtime, record, inherited, recorded: () => JSON.parse(readFileSync(record, "utf8")) };
}

function exchange(endpoint, message) {
  return new Promise((resolve, reject) => {
    const socket = createConnection(endpoint);
    const chunks = [];
    socket.once("error", reject);
    socket.once("connect", () => socket.write(JSON.stringify(message) + "\n"));
    socket.on("data", chunk => chunks.push(chunk));
    socket.once("end", () => resolve(JSON.parse(Buffer.concat(chunks).toString("utf8"))));
  });
}

test("the desktop schema allows copying text and screenshots, but no clipboard reads or path-like output names", () => {
  const validate = createMessageValidator(capability, {});
  const accepted = [
    { method: "clipboard.copy_text", params: { text: "line 1\n\tæøå" } },
    { method: "screenshot.capture", params: {} },
    { method: "screenshot.capture", params: { output: "DP-2" } },
    { method: "screenshot.capture", params: { region: { x: -10, y: 0, width: 640, height: 480 } } },
  ];
  for (const message of accepted) assert.doesNotThrow(() => validate({ id: 1, ...message }), JSON.stringify(message));
  const rejected = [
    { method: "clipboard.read_text", params: {} },
    { method: "clipboard.copy_text", params: { text: "" } },
    { method: "clipboard.copy_text", params: { text: "x".repeat(61441) } },
    { method: "clipboard.copy_text", params: { text: "x", type: "image/png" } },
    { method: "screenshot.capture", params: { output: "../DP-2" } },
    { method: "screenshot.capture", params: { output: "DP-2", region: { x: 0, y: 0, width: 1, height: 1 } } },
    { method: "screenshot.capture", params: { region: { x: 0, y: 0, width: 0, height: 1 } } },
    { method: "screenshot.capture", params: { path: "/home/user/.ssh/id_ed25519" } },
  ];
  for (const message of rejected) assert.throws(() => validate({ id: 1, ...message }), /IPC request/, JSON.stringify(message));
});

test("the handler passes copied text on stdin with only the compositor environment", async () => {
  const f = await fixture();
  const handler = createDesktopHandler(desktopAuthority(f.inherited), 5000);
  assert.equal(await handler({ method: "clipboard.copy_text", params: { text: "første linje\n$(id)" } }), undefined);
  const call = f.recorded();
  assert.deepEqual(call.args, ["--type", "text/plain;charset=utf-8"]);
  assert.equal(call.input, "første linje\n$(id)");
  assert.deepEqual(call.env, ["PATH", "WAYLAND_DISPLAY", "XDG_RUNTIME_DIR"]);
});

test("the handler returns screenshots as PNG data and forwards only validated geometry", async () => {
  const f = await fixture();
  const handler = createDesktopHandler(desktopAuthority(f.inherited), 5000);
  const full = await handler({ method: "screenshot.capture", params: {} });
  assert.deepEqual(full, { mediaType: "image/png", data: Buffer.from([0x89, 0x50, 0x4e, 0x47, 0, 255]).toString("base64") });
  assert.deepEqual(f.recorded().args, ["-t", "png", "-"]);
  await handler({ method: "screenshot.capture", params: { region: { x: -5, y: 10, width: 20, height: 30 } } });
  assert.deepEqual(f.recorded().args, ["-t", "png", "-g", "-5,10 20x30", "-"]);
  await handler({ method: "screenshot.capture", params: { output: "DP-2" } });
  assert.deepEqual(f.recorded().args, ["-t", "png", "-o", "DP-2", "-"]);
});

test("tool failures and hangs reject instead of returning partial results", async () => {
  const failing = await fixture({ grimBody: 'process.stdout.write("partial"); process.exit(1);' });
  await assert.rejects(createDesktopHandler(desktopAuthority(failing.inherited), 5000)({ method: "screenshot.capture", params: {} }), /exited with 1/);
  const hanging = await fixture({ grimBody: "setInterval(() => {}, 1000);" });
  await assert.rejects(createDesktopHandler(desktopAuthority(hanging.inherited), 300)({ method: "screenshot.capture", params: {} }), /timed out/);
});

test("desktop authority requires a real Wayland socket and absolute executables", async () => {
  const f = await fixture();
  assert.equal(desktopAuthority({ ...f.inherited, WAYLAND_DISPLAY: undefined }), undefined);
  assert.throws(() => desktopAuthority({ ...f.inherited, WAYLAND_DISPLAY: "../wl" }), /Invalid inherited Wayland display/);
  writeFileSync(join(f.runtime, "plain"), "");
  assert.throws(() => desktopAuthority({ ...f.inherited, WAYLAND_DISPLAY: "plain" }), /existing Unix socket/);
  assert.throws(() => desktopAuthority({ ...f.inherited, PI_DESKTOP_GRIM: "grim" }), /absolute executables/);
  assert.throws(() => desktopAuthority({ ...f.inherited, PI_DESKTOP_PATH: "bin" }), /absolute directory/);
});

test("the broker exports a private endpoint that serves pi-desktop and rejects other methods", async () => {
  const f = await fixture();
  let endpoint;
  await withDesktopBroker({ PI_DESKTOP_SOCKET: "/forged" }, f.inherited, f.home, capability, async environment => {
    endpoint = environment.PI_DESKTOP_SOCKET;
    assert.ok(endpoint.startsWith(join(f.home, ".pi-ipc") + "/"));
    const output = join(f.root, "shot.png");
    await main(["screenshot", "--region", "0,0,10x10", output], environment);
    assert.deepEqual([...readFileSync(output)], [0x89, 0x50, 0x4e, 0x47, 0, 255]);
    await main(["copy", "hello", "world"], environment);
    assert.equal(f.recorded().input, "hello world");
    const denied = await exchange(endpoint, { id: 2, method: "clipboard.read_text", params: {} });
    assert.equal(denied.ok, false);
  });
  assert.equal(existsSync(endpoint), false);
});

test("without an inherited desktop session the broker is not exported", async () => {
  const f = await fixture();
  let seen;
  await withDesktopBroker({ PI_DESKTOP_SOCKET: "/forged" }, { ...f.inherited, WAYLAND_DISPLAY: undefined }, f.home, capability, async environment => { seen = environment; });
  assert.equal(Object.hasOwn(seen, "PI_DESKTOP_SOCKET"), false);
});

test("pi-desktop parses screenshot geometry and rejects ambiguous selections", () => {
  assert.deepEqual(parseArguments(["screenshot", "--region", "-1,2,30x40", "a.png"]), {
    method: "screenshot.capture", params: { region: { x: -1, y: 2, width: 30, height: 40 } }, file: "a.png",
  });
  assert.deepEqual(parseArguments(["copy"]), { method: "clipboard.copy_text", text: undefined });
  assert.throws(() => parseArguments(["screenshot", "--output", "DP-1", "--region", "0,0,1x1", "a.png"]), /either --output or --region/);
  assert.throws(() => parseArguments(["screenshot", "--region", "0,0,1", "a.png"]), /X,Y,WxH/);
  assert.throws(() => parseArguments(["paste"]), /Usage/);
});
