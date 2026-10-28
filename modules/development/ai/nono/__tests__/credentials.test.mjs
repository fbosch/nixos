import assert from "node:assert/strict";
import { mkdirSync, mkdtempSync, rmSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { test } from "node:test";
import { assertCredentialSourceGrants, credentialDefinitions, credentialEnvironmentForDirenv, prepareCredentialEnvironment } from "../scripts/credentials.mjs";

test("Exa API and MCP share a supervisor-only file source and raw-key header", () => {
  for (const [name, upstream] of [["exa", "https://api.exa.ai"], ["exa_mcp", "https://mcp.exa.ai"]]) {
    const definition = credentialDefinitions[name];
    assert.deepEqual(definition.route, {
      upstream, env_var: "EXA_API_KEY", inject_header: "x-api-key", credential_format: "{}",
    });
    assert.deepEqual(definition.source, {
      type: "file", path: "/run/secrets/exa-api-key", sops: { file: "apis", key: "exa-api-key" },
    });
  }
  assert.deepEqual(credentialEnvironmentForDirenv({ EXA_API_KEY: "synthetic-exa-key", OTHER: "kept" }), { OTHER: "kept" });
  assert.throws(() => prepareCredentialEnvironment({ EXA_API_KEY: "synthetic-exa-key" }, {}, "/home/user"), /Exa credential environment/);
  assert.throws(() => prepareCredentialEnvironment({}, { EXA_API_KEY: "synthetic-exa-key" }, "/home/user"), /Exa credential environment/);
});

function docs(path) {
  return {
    docs: {
      label: "Docs",
      route: { upstream: "https://docs.example.test", env_var: "DOCS_API_KEY", inject_header: "x-api-key" },
      source: { type: "file", path },
      aliases: ["DOCS_TOKEN"],
      environment: { unset: ["DOCS_DEBUG"], set: { DOCS_CONFIG: "$HOME/.config/docs" } },
      capture: { timeout_secs: 10, cache_ttl_secs: 300 },
    },
  };
}

test("an additional declared MCP inherits all environment protection without a provider handler", () => {
  const definitions = docs("/run/secrets/docs-api-key");
  const environment = { DOCS_API_KEY: "synthetic-docs-key", DOCS_TOKEN: "synthetic-alias", NONO_ALLOW: "/", OTHER: "kept" };
  assert.deepEqual(credentialEnvironmentForDirenv(environment, definitions), { OTHER: "kept" });
  for (const name of ["DOCS_API_KEY", "DOCS_TOKEN"]) {
    assert.throws(() => prepareCredentialEnvironment({ [name]: "synthetic-docs-key" }, {}, "/home/user", definitions), /Docs credential environment/);
    assert.throws(() => prepareCredentialEnvironment({}, { [name]: "synthetic-docs-key" }, "/home/user", definitions), /Docs credential environment/);
  }
  assert.deepEqual(prepareCredentialEnvironment({}, { DOCS_CONFIG: "/project", DOCS_DEBUG: "1", OTHER: "kept" }, "/home/user", definitions), {
    DOCS_CONFIG: "/home/user/.config/docs", OTHER: "kept",
  });
});

test("an additional file-backed MCP gets secret-path protection from its declaration", () => {
  const root = mkdtempSync(join(tmpdir(), "pi-declared-credential-"));
  try {
    const safe = join(root, "work");
    const store = join(root, "secrets");
    mkdirSync(safe);
    mkdirSync(store);
    const secret = join(store, "docs-api-key");
    writeFileSync(secret, "synthetic-docs-key", { mode: 0o400 });
    const definitions = docs(secret);
    assert.doesNotThrow(() => assertCredentialSourceGrants(["--read", safe], safe, root, {}, {}, definitions));
    for (const grant of [secret, store, root]) {
      assert.throws(() => assertCredentialSourceGrants(["--read", grant], safe, root, {}, {}, definitions), /Docs credential store overlaps/);
    }
  } finally {
    rmSync(root, { recursive: true, force: true });
  }
});

test("credential declarations fail closed on invalid environment names or source types", () => {
  for (const value of [
    { ...docs("/run/secrets/docs").docs, route: { env_var: "INVALID-NAME" } },
    { ...docs("/run/secrets/docs").docs, route: {} },
    { ...docs("/run/secrets/docs").docs, source: { type: "unsupported" } },
  ]) {
    assert.throws(() => credentialEnvironmentForDirenv({}, { docs: value }), /Invalid credential/);
  }
});

test("supervisor paths cannot be selected through project environment variables", () => {
  const definitions = docs("/run/secrets/docs");
  definitions.docs.environment.set.DOCS_CONFIG = "$PROJECT_SECRETS";
  assert.throws(() => prepareCredentialEnvironment({}, { PROJECT_SECRETS: "/project" }, "/home/user", definitions), /only reference HOME/);
});
