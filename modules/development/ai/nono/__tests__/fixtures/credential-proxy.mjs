export function proxyFixtureSource(options = {}) {
  return `
Promise.all([import("node:http"), import("node:fs")]).then(([http, fs]) => {
  const options = ${JSON.stringify(options)};
  if (process.argv[2] !== "proxy") throw new Error("expected standalone proxy, not sandbox run");
  if (options.pidFile) fs.writeFileSync(options.pidFile, String(process.pid));
  if (options.recordFile) fs.writeFileSync(options.recordFile, JSON.stringify({
    args: process.argv.slice(2),
    ghConfig: process.env.GH_CONFIG_DIR,
    token: process.env.NONO_PROXY_PASS,
    nodeOptions: process.env.NODE_OPTIONS,
    bashEnv: process.env.BASH_ENV,
    contextKey: process.env.CONTEXT7_API_KEY,
  }));
  if (options.fail) process.exit(23);
  if (options.noReady) { setInterval(() => {}, 1000); return; }
  const profile = JSON.parse(fs.readFileSync(process.argv[process.argv.indexOf("--profile") + 1], "utf8"));
  const server = http.createServer((request, response) => {
    if (request.headers.authorization !== "Bearer " + process.env.NONO_PROXY_PASS) {
      response.writeHead(401).end(); return;
    }
    const name = request.url.split("/")[1];
    const route = profile.network?.custom_credentials?.[name];
    if (!route) { response.writeHead(404).end(); return; }
    const target = new URL(request.url.slice(name.length + 1), route.upstream);
    const upstream = http.request(target, {
      method: request.method,
      headers: { ...request.headers, authorization: "Bearer fixture-upstream-secret" },
    }, (upstreamResponse) => {
      response.writeHead(upstreamResponse.statusCode, upstreamResponse.headers);
      upstreamResponse.pipe(response);
    });
    upstream.on("error", () => response.writeHead(502).end());
    request.pipe(upstream);
  });
  const stop = () => {
    if (options.ignoreInterrupt) return;
    server.close(() => process.exit(0));
  };
  process.on("SIGINT", stop);
  process.on("SIGTERM", stop);
  server.listen(0, "127.0.0.1", () => {
    const token = process.env.NONO_PROXY_PASS;
    const host = options.invalidHost ? "example.com" : "127.0.0.1";
    const output = "  proxy URL: http://nono:" + token + "@" + host + ":" + server.address().port + "\\n" +
      (options.trustBundle ? "  TLS interception trust bundle: " + options.trustBundle + "\\n" : "") +
      "  Press Ctrl-C to stop.\\n";
    if (options.splitStartup) {
      process.stdout.write(output.slice(0, 25));
      setTimeout(() => process.stdout.write(output.slice(25)), 10);
    } else process.stdout.write(output);
    if (options.exitAfterReady) setTimeout(() => process.exit(24), 100);
  });
});
`;
}
