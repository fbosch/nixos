import assert from "node:assert/strict";
import { spawn } from "node:child_process";
import { once } from "node:events";
import { createConnection, createServer } from "node:net";
import { createInterface } from "node:readline";

const initialize = {
  jsonrpc: "2.0", id: 1, method: "initialize",
  params: { protocolVersion: "2024-11-05", capabilities: {}, clientInfo: { name: "probe", version: "1" } },
};

if (process.argv[2] === "--stdio-server") {
  const input = createInterface({ input: process.stdin });
  input.on("line", (line) => {
    const request = JSON.parse(line);
    assert.equal(request.method, "initialize");
    process.stdout.write(JSON.stringify({
      jsonrpc: "2.0", id: request.id,
      result: { protocolVersion: "2024-11-05", capabilities: {}, serverInfo: { name: "stdio-fixture", version: "1" } },
    }) + "\n");
    input.close();
    process.stdin.destroy();
  });
} else {
  const { sockets, deniedSockets = [], bindPath, deniedBindPath, url } = JSON.parse(process.argv[2]);
  assert.ok(process.env.PI_NVIM_ASK_SOCKET, "selected Pi Ask socket must remain available");
  const connected = [];
  for (const path of sockets) {
    const socket = createConnection(path);
    try {
      await new Promise((resolve, reject) => {
        socket.once("connect", resolve);
        socket.once("error", reject);
        socket.setTimeout(3000, () => reject(new Error(`Socket check timed out: ${path}`)));
      });
      connected.push(path);
    } finally {
      socket.destroy();
    }
  }
  const denied = [];
  for (const path of deniedSockets) {
    const socket = createConnection(path);
    try {
      await assert.rejects(once(socket, "connect"), error => ["EACCES", "EPERM"].includes(error.code));
      denied.push(path);
    } finally {
      socket.destroy();
    }
  }
  if (deniedBindPath) {
    const deniedListener = createServer();
    try {
      await assert.rejects(async () => {
        deniedListener.listen(deniedBindPath);
        await once(deniedListener, "listening");
      }, error => ["EACCES", "EPERM"].includes(error.code));
    } finally {
      deniedListener.close();
    }
  }

  const listener = createServer();
  try {
    listener.listen(bindPath);
    await once(listener, "listening");
  } finally {
    listener.close();
  }

  const child = spawn(process.execPath, [process.argv[1], "--stdio-server"], {
    stdio: ["pipe", "pipe", "pipe"],
  });
  const exited = once(child, "exit");
  const lines = createInterface({ input: child.stdout });
  const reply = once(lines, "line");
  let stderr = "";
  child.stderr.setEncoding("utf8").on("data", (chunk) => { stderr += chunk; });
  child.stdin.end(JSON.stringify(initialize) + "\n");
  const [line] = await reply;
  const [code, signal] = await exited;
  assert.equal(code, 0, stderr);
  assert.equal(signal, null);
  const stdio = JSON.parse(line);
  assert.equal(stdio.id, initialize.id);

  const response = await fetch(url, {
    method: "POST", headers: { "content-type": "application/json" },
    body: JSON.stringify(initialize), signal: AbortSignal.timeout(5000),
  });
  assert.equal(response.status, 200);
  const http = await response.json();
  assert.equal(http.id, initialize.id);
  console.log(JSON.stringify({ connected, denied, bound: true, stdio: stdio.result.serverInfo.name, http: http.result.serverInfo.name }));
}
