import { spawn } from "node:child_process";
import { accessSync, constants, statSync } from "node:fs";
import { isAbsolute, join } from "node:path";
import { withFilterHelper } from "./ipc-bootstrap.mjs";
import { createImageOpener } from "./desktop-images.mjs";

// Screenshots return as base64 in one response line; bound the PNG before encoding.
const maxImageBytes = 48 * 1024 * 1024;
const displayName = /^[A-Za-z0-9._-]{1,64}$/;

function executable(path) {
  if (typeof path !== "string" || !isAbsolute(path) || !statSync(path).isFile()) return false;
  accessSync(path, constants.X_OK);
  return true;
}

// Resolve desktop authority from the launch environment captured before project environment loading.
export function desktopAuthority(inherited) {
  const { WAYLAND_DISPLAY: display, XDG_RUNTIME_DIR: runtime, PI_DESKTOP_WL_COPY: wlCopy, PI_DESKTOP_GRIM: grim, PI_DESKTOP_PATH: path } = inherited;
  if (!display || !runtime || !wlCopy || !grim || !path) return undefined;
  if (!isAbsolute(runtime) || !(isAbsolute(display) || displayName.test(display))) throw new Error("Invalid inherited Wayland display");
  if (!statSync(isAbsolute(display) ? display : join(runtime, display)).isSocket()) throw new Error("Inherited Wayland display must be an existing Unix socket");
  if (!executable(wlCopy) || !executable(grim)) throw new Error("Desktop broker tools must be absolute executables");
  if (!isAbsolute(path) || !statSync(path).isDirectory()) throw new Error("Desktop broker PATH must be an absolute directory");
  let image;
  if (inherited.PI_DESKTOP_IMAGE_VIEWER && inherited.DBUS_SESSION_BUS_ADDRESS) {
    const viewer = inherited.PI_DESKTOP_IMAGE_VIEWER;
    const bus = inherited.DBUS_SESSION_BUS_ADDRESS;
    const match = /^unix:path=([^,;]+)(?:,guid=[0-9a-f]{32})?$/.exec(bus);
    if (!executable(viewer) || !match || !isAbsolute(match[1]) || !statSync(match[1]).isSocket()) throw new Error("Invalid inherited image-viewer authority");
    const data = inherited.PI_DESKTOP_IMAGE_DATA;
    if (typeof data !== "string" || !isAbsolute(data) || !statSync(join(data, "mime", "mime.cache")).isFile()) throw new Error("Image viewer requires a pinned MIME database");
    image = { viewer, bus, data };
  }
  return { display, runtime, wlCopy, grim, path, image };
}

function run(binary, args, authority, timeoutMs, input) {
  return new Promise((resolve, reject) => {
    // Only the compositor connection and a fixed tool PATH cross into the tools; wl-copy execs cat from PATH.
    const child = spawn(binary, args, {
      env: { WAYLAND_DISPLAY: authority.display, XDG_RUNTIME_DIR: authority.runtime, PATH: authority.path },
      // wl-copy forks a clipboard server that keeps inherited pipes open; only stdout is collected.
      stdio: [input === undefined ? "ignore" : "pipe", input === undefined ? "pipe" : "ignore", "ignore"],
    });
    const chunks = [];
    let size = 0;
    const timer = setTimeout(() => { child.kill("SIGKILL"); reject(new Error("Desktop tool timed out")); }, timeoutMs);
    child.once("error", error => { clearTimeout(timer); reject(error); });
    child.stdout?.on("data", chunk => {
      size += chunk.length;
      if (size > maxImageBytes) { child.kill("SIGKILL"); return; }
      chunks.push(chunk);
    });
    child.once("exit", code => {
      clearTimeout(timer);
      if (size > maxImageBytes) return reject(new Error("Screenshot exceeds the broker limit"));
      if (code !== 0) return reject(new Error(`Desktop tool exited with ${code}`));
      resolve(Buffer.concat(chunks));
    });
    if (input !== undefined) child.stdin.end(input);
  });
}

function launchImage(path, authority, directory) {
  return new Promise((resolve, reject) => {
    // The fixed viewer receives only desktop authority and a private HOME, never agent-selected commands or environment.
    const child = spawn(authority.image.viewer, ["--", path], {
      detached: true, stdio: "ignore",
      env: {
        WAYLAND_DISPLAY: authority.display, XDG_RUNTIME_DIR: authority.runtime, PATH: authority.path,
        DBUS_SESSION_BUS_ADDRESS: authority.image.bus, HOME: directory,
        XDG_CONFIG_HOME: directory, XDG_CACHE_HOME: directory,
        // NixOS has no /usr/share/mime; preserve only the pinned MIME data, not the host XDG search path.
        XDG_DATA_DIRS: authority.image.data,
        GSETTINGS_BACKEND: "memory", GIO_USE_VFS: "local", LANG: "C.UTF-8",
      },
    });
    let timer;
    child.once("error", error => { clearTimeout(timer); reject(error); });
    child.once("exit", code => {
      clearTimeout(timer);
      if (code === 0) resolve();
      else reject(new Error("Image viewer failed to start"));
    });
    child.once("spawn", () => {
      // A new viewer stays alive; an existing viewer may acknowledge through D-Bus and exit immediately.
      timer = setTimeout(resolve, 250);
      child.unref();
    });
  });
}

export function createDesktopHandler(authority, timeoutMs, imageDirectory) {
  const images = authority.image && imageDirectory
    ? createImageOpener(imageDirectory, path => launchImage(path, authority, imageDirectory))
    : undefined;
  const handle = async request => {
    if (request.method === "image.open") {
      if (!images) throw new Error("Image-opening broker is unavailable");
      return images.open(request.params);
    }
    if (request.method === "clipboard.copy_text") {
      // An explicit type skips wl-copy's MIME sniffing through xdg-mime.
      await run(authority.wlCopy, ["--type", "text/plain;charset=utf-8"], authority, timeoutMs, request.params.text);
      return undefined;
    }
    if (request.method === "screenshot.capture") {
      const { output, region } = request.params;
      const args = ["-t", "png"];
      if (output !== undefined) args.push("-o", output);
      if (region !== undefined) args.push("-g", `${region.x},${region.y} ${region.width}x${region.height}`);
      const image = await run(authority.grim, [...args, "-"], authority, timeoutMs);
      return { mediaType: "image/png", data: image.toString("base64") };
    }
    throw new Error("Unsupported desktop operation");
  };
  return Object.assign(handle, { close: () => images?.close() });
}

export async function withDesktopBroker(environment, inherited, home, capability, run) {
  const bound = { ...environment };
  delete bound[capability.socketEnvironment];
  const authority = desktopAuthority(inherited);
  if (!authority) return run(bound);
  return withFilterHelper(bound, home, capability, { desktop: authority }, run);
}
