import { readFileSync, writeFileSync } from "node:fs";
import { createConnection } from "node:net";
import { pathToFileURL } from "node:url";
import { createDesktopHandler, desktopAuthority } from "./desktop-broker.mjs";

const usage = `Usage:
  pi-desktop copy [TEXT...]        Copy TEXT, or standard input, to the clipboard
  pi-desktop screenshot [--output NAME | --region X,Y,WxH] FILE
                                   Capture all outputs, one output or a region as PNG`;

export function parseArguments(args) {
  const [command, ...rest] = args;
  if (command === "copy") return { method: "clipboard.copy_text", text: rest.length > 0 ? rest.join(" ") : undefined };
  if (command !== "screenshot") throw new Error(usage);
  const params = {};
  let file;
  for (let index = 0; index < rest.length; index++) {
    const value = rest[index + 1];
    if (rest[index] === "--output" && value) { params.output = value; index++; continue; }
    if (rest[index] === "--region" && value) {
      const match = /^(-?\d+),(-?\d+),(\d+)x(\d+)$/.exec(value);
      if (!match) throw new Error("--region must look like X,Y,WxH");
      params.region = { x: Number(match[1]), y: Number(match[2]), width: Number(match[3]), height: Number(match[4]) };
      index++;
      continue;
    }
    if (rest[index].startsWith("--") || file !== undefined) throw new Error(usage);
    file = rest[index];
  }
  if (!file) throw new Error(usage);
  if (params.output && params.region) throw new Error("Use either --output or --region");
  return { method: "screenshot.capture", params, file };
}

function request(endpoint, message) {
  return new Promise((resolve, reject) => {
    const socket = createConnection(endpoint);
    const chunks = [];
    socket.once("error", reject);
    socket.once("connect", () => socket.write(JSON.stringify(message) + "\n"));
    socket.on("data", chunk => chunks.push(chunk));
    socket.once("end", () => {
      try {
        const response = JSON.parse(Buffer.concat(chunks).toString("utf8"));
        if (response.ok !== true) throw new Error("The desktop broker rejected the request");
        resolve(response.result);
      } catch (error) { reject(error); }
    });
  });
}

export async function main(args, environment = process.env) {
  const parsed = parseArguments(args);
  const params = parsed.method === "clipboard.copy_text"
    ? { text: parsed.text ?? readFileSync(0, "utf8") }
    : parsed.params;
  const message = { id: 1, method: parsed.method, params };
  let result;
  if (environment.PI_DESKTOP_SOCKET) {
    result = await request(environment.PI_DESKTOP_SOCKET, message);
  } else {
    // Ordinary sandboxes reach the compositor directly; the restricted profile exports a broker socket.
    const authority = desktopAuthority(environment);
    if (!authority) throw new Error("No desktop session: WAYLAND_DISPLAY is unset or the broker is unavailable");
    result = await createDesktopHandler(authority, 8000)(message);
  }
  if (parsed.method === "screenshot.capture") {
    if (result?.mediaType !== "image/png" || typeof result.data !== "string") throw new Error("Invalid screenshot response");
    writeFileSync(parsed.file, Buffer.from(result.data, "base64"));
  }
}

if (process.argv[1] && import.meta.url === pathToFileURL(process.argv[1]).href) {
  main(process.argv.slice(2)).catch(error => {
    console.error(`pi-desktop: ${error instanceof Error ? error.message : String(error)}`);
    process.exitCode = 1;
  });
}
