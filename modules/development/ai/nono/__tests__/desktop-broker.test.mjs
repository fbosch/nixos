import assert from "node:assert/strict";
import { once } from "node:events";
import { spawn } from "node:child_process";
import { existsSync, mkdirSync, mkdtempSync, readFileSync, realpathSync, rmSync, writeFileSync } from "node:fs";
import { createConnection, createServer } from "node:net";
import { join } from "node:path";
import { afterEach, test } from "node:test";
import { randomBytes, randomUUID } from "node:crypto";
import { png } from "./fixtures/png.mjs";
import { createDesktopHandler, desktopAuthority } from "../scripts/ipc/providers/desktop/broker.mts";
import { createMessageValidator, defaultCapabilities } from "../scripts/ipc/policy.mts";
import { main, parseArguments } from "../scripts/pi-desktop.mts";
import { withScoped } from "./fixtures/scoped.mjs";
import { desktopProvider } from "../scripts/ipc/providers/desktop/provider.mts";
import { session } from "./fixtures/ipc-provider.mjs";

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
  // macOS libSystem adds __CF_USER_TEXT_ENCODING to every process; it is not passed by the broker.
  const wlCopy = tool(join(root, "wl-copy"), `fs.writeFileSync(${JSON.stringify(record)}, JSON.stringify({ args: process.argv.slice(2), env: Object.keys(process.env).filter(name => name !== "__CF_USER_TEXT_ENCODING").sort(), input: fs.readFileSync(0, "utf8") }));`);
  const grim = tool(join(root, "grim"), grimBody ?? `fs.writeFileSync(${JSON.stringify(record)}, JSON.stringify({ args: process.argv.slice(2) })); process.stdout.write(Buffer.from([0x89, 0x50, 0x4e, 0x47, 0, 255]));`);
  const imageData = join(root, "data");
  mkdirSync(join(imageData, "mime"), { recursive: true });
  writeFileSync(join(imageData, "mime", "mime.cache"), "fixture");
  const inherited = { WAYLAND_DISPLAY: "wl", XDG_RUNTIME_DIR: runtime, PI_DESKTOP_WL_COPY: wlCopy, PI_DESKTOP_GRIM: grim, PI_DESKTOP_PATH: root, PI_DESKTOP_IMAGE_DATA: imageData };
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

test("image opening uses the inherited fixed viewer and bus, not project values", async () => {
  const f = await fixture();
  const bus = createServer(socket => socket.destroy());
  servers.push(bus);
  const busPath = join(f.runtime, "bus");
  bus.listen(busPath); await once(bus, "listening");
  // The broker reports success after a short startup grace period, so the fixture signals when its record is complete.
  const viewer = tool(join(f.root, "viewer"), `
    const args = process.argv.slice(2);
    fs.writeFileSync(${JSON.stringify(f.record)}, JSON.stringify({args, env:process.env, image:fs.readFileSync(args[1]).toString("base64")}));
    require("node:net").connect(${JSON.stringify(busPath)}).on("error", () => {});
  `);
  const inherited = {...f.inherited,PI_DESKTOP_IMAGE_VIEWER:viewer,DBUS_SESSION_BUS_ADDRESS:`unix:path=${busPath}`};
  let path;
  await withScoped(desktopProvider.start({PI_DESKTOP_IMAGE_VIEWER:"/untrusted",DBUS_SESSION_BUS_ADDRESS:"/untrusted",PI_DESKTOP_IMAGE_DATA:"/untrusted", XDG_DATA_DIRS:"/untrusted", SECRET:"not forwarded"}, session(inherited, f.home), capability), async environment => {
    const bytes=png();
    const launched=once(bus,"connection");
    const response=await exchange(environment.PI_DESKTOP_SOCKET,{id:1,method:"image.open",params:{imageId:randomUUID(),offset:0,totalBytes:bytes.length,data:bytes.toString("base64")}});
    assert.equal(response.ok,true);
    assert.deepEqual(response.result,{complete:true});
    await launched;
    const record=f.recorded();
    assert.equal(record.args[0],"--");
    path=record.args[1];
    assert.ok(path.startsWith(join(f.home,".pi-ipc")+"/"));
    assert.deepEqual(Buffer.from(record.image,"base64"),bytes);
    assert.equal(record.env.DBUS_SESSION_BUS_ADDRESS,`unix:path=${busPath}`);
    assert.equal(record.env.XDG_DATA_DIRS, f.inherited.PI_DESKTOP_IMAGE_DATA);
    assert.equal(record.env.SECRET,undefined);
    assert.equal(record.env.NODE_OPTIONS,undefined);
    assert.equal(record.env.GSETTINGS_BACKEND,"memory");
    const relaunched=once(bus,"connection");
    const repeated=await exchange(environment.PI_DESKTOP_SOCKET,{id:3,method:"image.open",params:{imageId:randomUUID(),offset:0,totalBytes:bytes.length,data:bytes.toString("base64")}});
    assert.equal(repeated.ok,true);
    await relaunched;
    assert.equal(f.recorded().args[1],path,"repeat broker requests reuse the same private file");
    for (const params of [{path:"/etc/passwd"},{url:"https://example.com/a.png"},{imageId:randomUUID(),offset:0,totalBytes:9,data:"PHN2Zy8+"},{imageId:randomUUID(),offset:0,totalBytes:bytes.length,data:bytes.toString("base64"),command:"sh"}]) {
      const denied=await exchange(environment.PI_DESKTOP_SOCKET,{id:2,method:"image.open",params});
      assert.equal(denied.ok,false);
    }
  });
  assert.equal(existsSync(path),false,"helper shutdown removes owned image files");
});

test("the broker exports a private endpoint that serves pi-desktop and rejects other methods", async () => {
  const f = await fixture();
  let endpoint;
  await withScoped(desktopProvider.start({ PI_DESKTOP_SOCKET: "/forged" }, session(f.inherited, f.home), capability), async environment => {
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

test("the sanitized image viewer identifies PNG using the pinned MIME database", {
  skip: !process.env.GIO_TEST_BINARY || !process.env.MIME_TEST_DATA,
}, async () => {
  const f = await fixture();
  const bus = createServer(socket => socket.end());
  servers.push(bus);
  const busPath = join(f.runtime, "bus");
  bus.listen(busPath); await once(bus, "listening");
  const viewer = tool(join(f.root, "mime-viewer"), `
    const result = require("node:child_process").spawnSync(${JSON.stringify(process.env.GIO_TEST_BINARY)}, ["info", "-a", "standard::content-type", process.argv[3]], {env:process.env,encoding:"utf8"});
    if (result.status !== 0) process.exit(1);
    fs.writeFileSync(${JSON.stringify(f.record)}, JSON.stringify({mime:result.stdout.match(/standard::content-type: (.+)/)?.[1]}));
  `);
  const inherited = {...f.inherited,PI_DESKTOP_IMAGE_VIEWER:viewer,PI_DESKTOP_IMAGE_DATA:process.env.MIME_TEST_DATA,DBUS_SESSION_BUS_ADDRESS:`unix:path=${busPath}`};
  await withScoped(desktopProvider.start({}, session(inherited, f.home), capability), async environment => {
    const bytes = png();
    const result = await exchange(environment.PI_DESKTOP_SOCKET,{id:"mime",method:"image.open",params:{imageId:randomUUID(),offset:0,totalBytes:bytes.length,data:bytes.toString("base64")}});
    assert.equal(result.ok,true);
    assert.equal(f.recorded().mime,"image/png");
  });
});
test("a fresh sandbox can open brokered images but cannot read broker files or connect to session D-Bus", {
  skip: process.platform !== "linux" || !process.env.NONO_TEST_BINARY,
  timeout: 20000,
}, async () => {
  const f = await fixture();
  let busConnections=0;
  const bus=createServer(socket=>{busConnections++;socket.end();});
  servers.push(bus);
  const busPath=join(f.runtime,"bus");bus.listen(busPath);await once(bus,"listening");
  const viewer=tool(join(f.root,"image-viewer"), `
    const socket=require("node:net").createConnection(process.env.DBUS_SESSION_BUS_ADDRESS.slice("unix:path=".length));
    socket.once("error",()=>{process.exitCode=1;});
    socket.once("connect",()=>{fs.writeFileSync(${JSON.stringify(f.record)},JSON.stringify({path:process.argv[3],bytes:fs.readFileSync(process.argv[3]).length}));socket.end();});
  `);
  const inherited={...f.inherited,PI_DESKTOP_IMAGE_VIEWER:viewer,DBUS_SESSION_BUS_ADDRESS:`unix:path=${busPath}`};
  const work=join(f.root,"work");mkdirSync(work);
  const temporary=join(f.root,"tmp");mkdirSync(temporary);
  const policy=join(f.root,"confined.json");
  writeFileSync(policy,JSON.stringify({extends:"default",filesystem:{read:["/nix/store"],allow:[work]},network:{block:true},linux:{af_unix_mediation:"pathname",sandbox_policy:"landlock"}}));
  await withScoped(desktopProvider.start({}, session(inherited, f.home), capability),async environment=>{
    const first=png();
    const seed=await exchange(environment.PI_DESKTOP_SOCKET,{id:"seed",method:"image.open",params:{imageId:randomUUID(),offset:0,totalBytes:first.length,data:first.toString("base64")}});
    assert.equal(seed.ok,true);
    const privateFile=f.recorded().path;
    const width=200,height=200,raster=randomBytes((width*4+1)*height);
    for(let row=0;row<height;row++)raster[row*(width*4+1)]=0;
    const bytes=png({width,height,raster});
    const script=join(work,"probe.cjs");
    writeFileSync(script,`
      const assert=require("node:assert/strict"),fs=require("node:fs"),net=require("node:net");
      const endpoint=process.env.PI_DESKTOP_SOCKET;
      const bytes=Buffer.from(${JSON.stringify(bytes.toString("base64"))},"base64");
      const request=params=>new Promise((resolve,reject)=>{
        const socket=net.createConnection(endpoint);let input="";socket.on("error",reject);
        socket.on("connect",()=>socket.write(JSON.stringify({id:1,method:"image.open",params})+"\\n"));
        socket.on("data",chunk=>input+=chunk);socket.on("end",()=>resolve(JSON.parse(input)));
      });
      (async()=>{
        const imageId=require("node:crypto").randomUUID();
        for(let offset=0;offset<bytes.length;offset+=32768){
          const part=bytes.subarray(offset,offset+32768);
          const response=await request({imageId,offset,totalBytes:bytes.length,data:part.toString("base64")});
          assert.equal(response.ok,true);assert.equal(response.result.complete,offset+part.length===bytes.length);
        }
        assert.throws(()=>fs.readFileSync(${JSON.stringify(privateFile)}),e=>["EACCES","EPERM"].includes(e.code));
        await new Promise((resolve,reject)=>{
          const socket=net.createConnection(${JSON.stringify(busPath)});
          socket.on("connect",()=>{socket.destroy();reject(new Error("session bus exposed"));});
          socket.on("error",error=>["EACCES","EPERM"].includes(error.code)?resolve():reject(error));
        });
        console.log("broker image opened; private files and D-Bus remain denied");
      })().catch(error=>{console.error(error);process.exitCode=1;});
    `);
    const child=spawn(process.env.NONO_TEST_BINARY,["run","--profile",policy,"--allow-unix-socket",environment.PI_DESKTOP_SOCKET,"--",process.execPath,script],{
      cwd:work,env:{HOME:f.home,PATH:process.env.PATH,TMPDIR:temporary,PI_DESKTOP_SOCKET:environment.PI_DESKTOP_SOCKET},stdio:["ignore","pipe","pipe"],
    });
    let output="";child.stdout.on("data",chunk=>output+=chunk);child.stderr.on("data",chunk=>output+=chunk);
    const [status,signal]=await once(child,"exit");
    assert.equal(signal,null,output);assert.equal(status,0,output);
    assert.equal(f.recorded().bytes,bytes.length);
    assert.equal(busConnections,2,"only the host-side viewer connects to D-Bus");
  });
});
test("without an inherited desktop session the broker is not exported", async () => {
  const f = await fixture();
  let seen;
  await withScoped(desktopProvider.start({ PI_DESKTOP_SOCKET: "/forged" }, session({ ...f.inherited, WAYLAND_DISPLAY: undefined }, f.home), capability), async environment => { seen = environment; });
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
