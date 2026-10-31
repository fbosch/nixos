import { closeSync, constants, fstatSync, openSync, readSync, watch } from "node:fs";
import { stripVTControlCharacters } from "node:util";

const MAX_READ_BYTES = 65536;

function notice(line) {
  const match = /^\s*(?:\d{4}-\d{2}-\d{2}T\S+\s+)?(WARN|ERROR)\s+(.*)$/.exec(stripVTControlCharacters(line));
  if (!match) return undefined;
  const level = match[1] === "ERROR" ? "error" : "warning";
  const message = match[2].includes("failed to wait for credential capture command")
    ? "Nono could not wait for the credential capture command."
    : match[2].includes("Credential loading error")
      ? "Nono could not load credentials."
      : level === "error" ? "Nono reported an error." : "Nono reported a warning.";
  return { message, level };
}

export function watchNonoDiagnostics(path, notify, seen = new Set()) {
  const fd = openSync(path, constants.O_RDONLY | constants.O_NOFOLLOW | constants.O_NONBLOCK);
  let watcher;
  let closed = false;
  const dispose = () => {
    if (closed) return;
    closed = true;
    watcher?.close();
    closeSync(fd);
  };
  const fail = () => {
    dispose();
    notify("Nono diagnostics could not be read.", "warning");
  };
  const drain = () => {
    if (closed) return;
    try {
      const size = fstatSync(fd).size;
      const offset = Math.max(0, size - MAX_READ_BYTES);
      const buffer = Buffer.alloc(Math.min(size, MAX_READ_BYTES));
      const length = readSync(fd, buffer, 0, buffer.length, offset);
      const lines = buffer.subarray(0, length).toString("utf8").split("\n");
      // The tail may start midway through a record; an unfinished final record waits for its newline.
      if (offset !== 0) lines.shift();
      lines.pop();
      for (const line of lines) {
        const item = notice(line);
        if (!item) continue;
        const key = `${item.level}:${item.message}`;
        if (seen.has(key)) continue;
        seen.add(key);
        // Raw proxy diagnostics can contain terminal controls or credentials.
        notify(item.message, item.level);
      }
    } catch {
      fail();
    }
  };
  try {
    const stat = fstatSync(fd);
    if (!stat.isFile() || stat.uid !== process.getuid() || (stat.mode & 0o077) !== 0) {
      throw new Error("Nono diagnostics must be an owner-only regular file");
    }
    // Watch before the initial drain so startup warnings and concurrent appends are both observed.
    watcher = watch(path, { persistent: false }, drain);
    watcher.on("error", fail);
    drain();
    return dispose;
  } catch (error) {
    dispose();
    throw error;
  }
}

export default function nonoDiagnostics(pi) {
  let dispose = () => {};
  const seen = new Set();
  pi.on("session_start", (_event, ctx) => {
    dispose();
    const path = process.env.PI_NONO_DIAGNOSTICS_FILE;
    if (!path) return;
    const notify = (message, level) => {
      if (ctx.hasUI) ctx.ui.notify(message, level);
      else process.stderr.write(`${message}\n`);
    };
    try {
      dispose = watchNonoDiagnostics(path, notify, seen);
    } catch {
      notify("Nono diagnostics could not be read.", "warning");
    }
  });
  pi.on("session_shutdown", () => {
    dispose();
    dispose = () => {};
  });
}
