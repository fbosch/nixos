import { lstatSync, realpathSync } from "node:fs";
import { tmpdir } from "node:os";
import { isAbsolute, join } from "node:path";

export function piAskArguments(environment) {
  const socket = environment.PI_NVIM_BROKER;
  if (!socket) return [];
  try {
    const launchId = environment.PI_NVIM_LAUNCH_ID;
    if (!/^[a-f0-9]{32}$/.test(launchId ?? "")) throw new Error("invalid launch ID");
    const uid = process.getuid();
    const runtime = realpathSync(environment.XDG_RUNTIME_DIR || tmpdir());
    const root = join(runtime, `pi-ask-${uid}`);
    const directory = join(root, launchId);
    const expected = join(directory, "broker.sock");
    if (!isAbsolute(socket) || socket !== expected || realpathSync(socket) !== expected) {
      throw new Error("socket must be the canonical per-launch broker endpoint");
    }
    for (const path of [root, directory]) {
      const stat = lstatSync(path);
      if (!stat.isDirectory() || stat.uid !== uid || (stat.mode & 0o777) !== 0o700) {
        throw new Error("broker directories must be private and owned by the current user");
      }
    }
    const stat = lstatSync(socket);
    if (!stat.isSocket() || stat.uid !== uid || (stat.mode & 0o777) !== 0o600) {
      throw new Error("broker must be a private socket owned by the current user");
    }
    return ["--allow-unix-socket", expected];
  } catch (error) {
    throw new Error(`Cannot grant Pi Ask broker access: ${error.message}`);
  }
}
