import assert from "node:assert/strict";
import { spawnSync } from "node:child_process";
import { mkdtemp, rm, writeFile } from "node:fs/promises";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { test } from "node:test";

const binary = process.env.PI_TEST_BINARY;
assert.ok(binary, "PI_TEST_BINARY must point to the compiled Pi executable");

// Extension imports resolve to the compiled SDK, including its embedded worker URL.
const extension = `
import assert from "node:assert/strict";
import { createCodemodeExtension } from "@earendil-works/pi-coding-agent";
export default async function () {
  let tool;
  createCodemodeExtension({ models: false })({
    registerTool: (definition) => { tool = definition; },
  });
  const ctx = {
    tools: [{
      name: "fixture_echo",
      description: "Return a fixture value",
      parameters: { type: "object", properties: { value: { type: "number" } } },
      outputSchema: { type: "number" },
    }],
    sessionManager: { getBranch: () => [] },
    executeTool: async (name, args) => {
      assert.equal(name, "fixture_echo");
      assert.deepEqual(args, { value: 42 });
      return {
        toolCall: { id: "compiled-worker/1" },
        isError: false,
        result: { content: [], structuredContent: args.value },
      };
    },
  };
  for (const code of ["return 42;", "return await tools.fixture_echo({ value: 42 });"]) {
    const result = await tool.execute("compiled-worker", {
      code: '// @options: {"timeout_ms": 10000}\\n' + code,
    }, undefined, undefined, ctx);
    const output = result.content.filter((item) => item.type === "text").map((item) => item.text).join("\\n");
    console.log(output);
    assert.notEqual(result.isError, true, output);
    assert.match(output, /Script completed/);
    assert.match(output, /\\n42(?:\\n|$)/);
  }
  console.log("PI_CODEMODE_COMPILED_WORKER_OK");
}
`;

test("compiled codemode worker evaluates scripts and bridges nested calls offline", async () => {
  const dir = await mkdtemp(join(tmpdir(), "pi-codemode-worker-"));
  try {
    const path = join(dir, "smoke.mjs");
    await writeFile(path, extension);
    const result = spawnSync(binary, [
      "--offline", "--no-extensions", "--no-skills", "--no-prompt-templates",
      "--no-context-files", "--no-themes", "--no-session", "-e", path, "--help",
    ], {
      cwd: dir,
      env: {
        HOME: dir,
        PATH: process.env.PATH,
        PI_CODING_AGENT_DIR: join(dir, "agent"),
        PI_OFFLINE: "1",
        PI_SKIP_VERSION_CHECK: "1",
        PI_TELEMETRY: "0",
      },
      encoding: "utf8",
      timeout: 30_000,
    });
    const output = `${result.stdout ?? ""}\n${result.stderr ?? ""}`;
    assert.ifError(result.error);
    assert.equal(result.status, 0, output);
    // --help can swallow extension errors and exit zero; require successful execution.
    assert.match(output, /PI_CODEMODE_COMPILED_WORKER_OK/, output);
    assert.doesNotMatch(output, /Script sandbox failed|Cannot find module/, output);
  } finally {
    await rm(dir, { recursive: true, force: true });
  }
});
