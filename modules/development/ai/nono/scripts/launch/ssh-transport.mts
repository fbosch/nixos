import { connect } from "node:net";
import { isAbsolute } from "node:path";

function proxyConnection(host: string | undefined, port: string | undefined): { proxy: URL; target: string } {
  if (!["ssh.dev.azure.com", "vs-ssh.visualstudio.com"].includes(host ?? "") || port !== "22") {
    throw new Error("only Azure DevOps SSH on port 22 is supported");
  }
  let proxy: URL;
  try {
    proxy = new URL(process.env.HTTP_PROXY || process.env.http_proxy || "");
  } catch {
    throw new Error("the nono HTTP proxy is missing or invalid");
  }
  if (proxy.protocol !== "http:" || proxy.hostname !== "127.0.0.1" || !proxy.port ||
      proxy.pathname !== "/" || proxy.search || proxy.hash) {
    throw new Error("SSH requires the local nono HTTP proxy");
  }
  return { proxy, target: `${host}:${port}` };
}

function tunnel(host: string | undefined, port: string | undefined): void {
  const { proxy, target } = proxyConnection(host, port);
  const credentials = proxy.username || proxy.password
    ? `${decodeURIComponent(proxy.username)}:${decodeURIComponent(proxy.password)}`
    : process.env.NONO_PROXY_TOKEN ? `nono:${process.env.NONO_PROXY_TOKEN}` : undefined;
  const authorization = credentials
    ? `Proxy-Authorization: Basic ${Buffer.from(credentials).toString("base64")}\r\n` : "";
  const socket = connect({ host: proxy.hostname, port: Number(proxy.port), allowHalfOpen: true });
  let header = Buffer.alloc(0);
  let established = false;
  let failed = false;
  function fail(message: string): void {
    if (failed) return;
    failed = true;
    console.error(`pi SSH: ${message}`);
    process.exitCode = 1;
    socket.destroy();
  }
  socket.setTimeout(30_000, () => fail("CONNECT handshake timed out"));
  socket.once("connect", () => socket.write(
    `CONNECT ${target} HTTP/1.1\r\nHost: ${target}\r\n${authorization}\r\n`,
  ));
  socket.on("error", () => fail("CONNECT proxy connection failed"));
  process.stdout.on("error", () => fail("SSH output closed"));
  process.stdin.on("error", () => fail("SSH input closed"));
  socket.once("end", () => {
    if (!established) fail("CONNECT proxy closed before establishing the tunnel");
    else {
      // OpenSSH waits for ProxyCommand to exit before closing stdin after the server's EOF.
      process.stdin.unpipe(socket);
      process.stdin.destroy();
      socket.end();
    }
  });
  socket.once("close", () => {
    if (!established) fail("CONNECT proxy closed before establishing the tunnel");
    process.stdin.destroy();
  });
  function readHeader(chunk: Buffer): void {
    header = Buffer.concat([header, chunk]);
    const end = header.indexOf("\r\n\r\n");
    if ((end === -1 && header.length > 16384) || end > 16384) return fail("CONNECT response headers exceeded their limit");
    if (end === -1) return;
    const status = /^HTTP\/1\.[01] ([0-9]{3})(?: |\r\n)/.exec(header.toString("latin1"));
    if (status?.[1] !== "200") return fail(`CONNECT proxy refused SSH (${status?.[1] ?? "invalid response"})`);
    established = true;
    socket.setTimeout(0);
    socket.removeListener("data", readHeader);
    // A proxy may send its response and the SSH banner in the same TCP packet.
    const banner = header.subarray(end + 4);
    if (banner.length) process.stdout.write(banner);
    socket.pipe(process.stdout);
    // Do not consume SSH input until CONNECT succeeds; stdin EOF must half-close, not discard output.
    process.stdin.pipe(socket);
  }
  socket.on("data", readHeader);
}

try {
  const [mode, first, second, ...args] = process.argv.slice(2);
  if (mode === "client") {
    if (!first || !second || !isAbsolute(first) || !isAbsolute(second)) throw new Error("missing pinned SSH executable or configuration");
    // Raw Pi and host-side launcher commands retain their native SSH configuration.
    process.execve!(first, [first, ...(process.env.NONO_CAP_FILE ? ["-F", second] : []), ...args], process.env);
  } else if (mode === "connect" && args.length === 0) {
    tunnel(first, second);
  } else {
    throw new Error("invalid SSH transport invocation");
  }
} catch {
  // Do not print URL/parser errors: they may include the proxy's session credential.
  console.error("pi SSH: invalid transport configuration or destination");
  process.exitCode = 1;
}
