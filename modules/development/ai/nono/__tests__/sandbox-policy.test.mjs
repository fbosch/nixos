import assert from "node:assert/strict";
import { mkdtempSync, rmSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { test } from "node:test";
import { grants, loadSandboxPolicy, sandboxPolicy } from "../scripts/shared/sandbox-policy.mts";

function load(mutate) {
  const root = mkdtempSync(join(tmpdir(), "pi-sandbox-policy-"));
  try {
    const policy = structuredClone(sandboxPolicy);
    mutate(policy);
    const path = join(root, "sandbox-policy.json");
    writeFileSync(path, JSON.stringify(policy));
    return loadSandboxPolicy(path);
  } finally {
    rmSync(root, { recursive: true, force: true });
  }
}

test("the bundled sandbox policy validates and cannot be modified at runtime", () => {
  assert.deepEqual(load(() => {}), sandboxPolicy);
  assert.throws(() => { sandboxPolicy.ssh.publicFiles.push("id_ed25519"); }, TypeError);
  assert.throws(() => { sandboxPolicy.filesystem.grants["pi-lens"].access = "read"; }, TypeError);
});

test("grants apply in name order", () => {
  const names = grants.map((grant) => grant.name);
  assert.deepEqual(names, Object.keys(sandboxPolicy.filesystem.grants).sort());
});

const rejected = {
  "a private SSH key as a readable client file": policy => policy.ssh.publicFiles.push("id_ed25519"),
  "a hidden file disguised as a public key": policy => policy.ssh.publicFiles.push(".pub"),
  "an absolute path": policy => policy.filesystem.agent.writableHomePaths.push("/etc"),
  "parent traversal": policy => policy.filesystem.shellStartup.home.push("dotfiles/../../etc"),
  "a dot segment": policy => policy.filesystem.agent.writableHomePaths.push("./cache"),
  "an unknown field": policy => { policy.extra = []; },
  "a writable single file": policy => { policy.filesystem.grants.file = { base: "home", path: "file", type: "file", access: "readwrite" }; },
  "an unknown base directory": policy => { policy.filesystem.grants.state = { base: "state", path: "x", type: "directory", access: "read" }; },
  "an invalid override variable": policy => { policy.filesystem.grants["pi-hashline"].override = "lowercase"; },
  "a nested agent runtime entry": policy => policy.filesystem.agent.runtimeEntries.push("extensions/cache"),
  "a configuration repository outside $HOME": policy => policy.exceptions.configurationRepositories.push(".."),
  "an unsupported version": policy => { policy.version = 2; },
  "an invalid grant name": policy => { policy.filesystem.grants["Bad Name"] = { base: "home", path: "x", type: "directory", access: "read" }; },
  "a disabled-grant marker, which Nix strips before serializing": policy => { policy.filesystem.grants["pi-lens"].enable = false; },
  "the IPC registry, which has its own file": policy => { policy.ipc = {}; },
};
for (const [name, mutate] of Object.entries(rejected)) {
  test(`the sandbox policy rejects ${name}`, () => {
    assert.throws(() => load(mutate), (error) => error._tag === "InvalidConfigError" && /Invalid sandbox policy/.test(error.message));
  });
}
