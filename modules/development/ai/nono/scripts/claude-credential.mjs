import { closeSync, constants, fstatSync, lstatSync, openSync, readSync } from "node:fs";
import { homedir } from "node:os";
import { join } from "node:path";
import { pathToFileURL } from "node:url";

const MAX_BYTES = 64 * 1024;
const MIN_VALIDITY_MS = 60_000;
const missing = "Claude CLI login is unavailable; log in with Claude on the host.";
const invalid = "Claude CLI credential store is invalid or unsafe.";
const expired = "Claude CLI access token is expired or near expiry; refresh the login with Claude on the host.";

export function captureClaudeAccessToken(home = homedir(), now = Date.now()) {
  const directory = join(home, ".claude");
  const path = join(directory, ".credentials.json");
  let descriptor;
  try {
    const parent = lstatSync(directory);
    if (!parent.isDirectory() || parent.uid !== process.getuid() || (parent.mode & 0o022) !== 0) throw new Error(invalid);
    // Never follow a credential-file symlink or block on a substituted FIFO.
    descriptor = openSync(path, constants.O_RDONLY | constants.O_NOFOLLOW | constants.O_NONBLOCK);
    const entry = fstatSync(descriptor);
    if (!entry.isFile() || entry.uid !== process.getuid() || entry.nlink !== 1 || (entry.mode & 0o077) !== 0 || entry.size > MAX_BYTES) {
      throw new Error(invalid);
    }
    const buffer = Buffer.alloc(MAX_BYTES + 1);
    let bytes = 0;
    while (bytes < buffer.length) {
      const count = readSync(descriptor, buffer, bytes, buffer.length - bytes, null);
      if (count === 0) break;
      bytes += count;
    }
    if (bytes > MAX_BYTES) throw new Error(invalid);
    const after = fstatSync(descriptor);
    if (entry.size !== after.size || entry.mtimeMs !== after.mtimeMs || entry.ctimeMs !== after.ctimeMs) throw new Error(invalid);
    let record;
    try { record = JSON.parse(buffer.subarray(0, bytes).toString("utf8")); }
    catch { throw new Error(invalid); }
    const oauth = record?.claudeAiOauth;
    if (!oauth || typeof oauth.accessToken !== "string" || oauth.accessToken.length > 8192 ||
        !/^[A-Za-z0-9._~+\/-]+=*$/.test(oauth.accessToken) ||
        !Number.isFinite(oauth.expiresAt) || !Array.isArray(oauth.scopes) || !oauth.scopes.includes("user:inference")) {
      throw new Error(invalid);
    }
    // This margin exceeds the proxy's 30-second cache TTL. Claude CLI retains ownership of refresh and rotation.
    if (oauth.expiresAt <= now + MIN_VALIDITY_MS) throw new Error(expired);
    return oauth.accessToken;
  } catch (error) {
    if ([missing, invalid, expired].includes(error.message)) throw error;
    throw new Error(error.code === "ENOENT" ? missing : invalid);
  } finally {
    if (descriptor !== undefined) closeSync(descriptor);
  }
}

if (process.argv[1] && import.meta.url === pathToFileURL(process.argv[1]).href) {
  try {
    if (process.argv.length !== 2) throw new Error(invalid);
    // stdout is consumed only by nono's host-side credential capture, never by the sandboxed agent.
    process.stdout.write(captureClaudeAccessToken());
  } catch (error) {
    console.error(error.message);
    process.exitCode = 1;
  }
}
