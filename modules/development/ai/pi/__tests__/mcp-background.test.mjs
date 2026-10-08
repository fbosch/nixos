import assert from "node:assert/strict";
import { readFile } from "node:fs/promises";
import { join } from "node:path";
import { test } from "node:test";
import { runInNewContext } from "node:vm";

const root = process.env.PI_TEST_PACKAGE;
assert.ok(root, "PI_TEST_PACKAGE must point to the unpacked Pi package");
const source = await readFile(join(root, "dist/extensions/mcp/index.js"), "utf8");

assert.match(
  source,
  /import \{ CODEMODE_TOOL_NAME, isCodemodeTool \} from "\.\.\/codemode\/tool\.js";/,
  "MCP session startup must import the codemode predicate used by discovery activation",
);

assert.match(
  source,
  /import \{ isToolSearchTool, TOOL_SEARCH_TOOL_NAME \} from "\.\.\/tool-search\/tool\.js";/,
  "MCP session startup must import the tool-search predicate used by discovery activation",
);

function fixture(exposure = "codemode", errors = []) {
  const handlers = new Map();
  const commands = new Map();
  const statuses = new Map();
  const notices = [];
  const connections = [];
  const tools = [{ name: "codemode" }, { name: "tool_search" }];
  class Connection {
    state = "connecting";
    tools = [];
    resources = [];
    constructor(options) {
      this.entry = options.entry;
      this.changed = () => options.onChange(this);
      this.ready = new Promise((resolve) => { this.finish = resolve; });
      connections.push(this);
    }
    getClient() { return this.ready; }
    async close() { this.finish(); }
    settle(state) { this.state = state; this.changed(); this.finish(); }
  }
  const factory = runInNewContext(
    source.replace(/^import .*;\n/gm, "").replace(/export default createMcpExtension\(\);/, "").replace(/^export /gm, "") + "\ncreateMcpExtension;",
    {
      process, AbortController, setImmediate, setTimeout, clearTimeout,
      join, resolve: join, getAgentDir: () => "/tmp/pi-mcp-test",
      openBrowser() {},
      mcpNamespace: (name) => `mcp__${name}`,
      CODEMODE_TOOL_NAME: "codemode", TOOL_SEARCH_TOOL_NAME: "tool_search",
      LIST_MCP_RESOURCES_TOOL: "list_mcp_resources",
      LIST_MCP_RESOURCE_TEMPLATES_TOOL: "list_mcp_resource_templates",
      READ_MCP_RESOURCE_TOOL: "read_mcp_resource",
      isCodemodeTool: (tool) => tool.name === "codemode",
      isToolSearchTool: (tool) => tool.name === "tool_search",
      loadMcpRuntime: async () => ({
        McpServerConnection: Connection,
        McpOAuthCredentialStore: class {}, McpServerLog: class {},
      }),
      showMcpManager: async () => {},
    },
  );
  const pi = {
    on: (name, handler) => handlers.set(name, handler),
    registerCommand: (name, command) => commands.set(name, command),
    registerToolRenderer() {},
    getMcpServers: () => [], getAllTools: () => tools,
    getActiveTools: () => ["codemode", "tool_search"], setActiveTools() {},
  };
  const ctx = {
    cwd: "/tmp", hasUI: true, mode: "tui", modelRegistry: {},
    ui: {
      setStatus: (key, status) => statuses.set(key, status),
      notify: (message) => notices.push(message),
    },
  };
  factory({ loadConfig: () => ({
    errors,
    servers: [{ name: "hung", source: "/tmp/mcp.json", config: { command: "fake", exposure } }],
  }) })(pi);
  return { handlers, commands, statuses, notices, connections, ctx };
}

async function promptly(operation) {
  let timer;
  try {
    await Promise.race([
      Promise.resolve(operation),
      new Promise((_, reject) => { timer = setTimeout(() => reject(new Error("blocked on MCP startup")), 100); }),
    ]);
  } finally { clearTimeout(timer); }
}

for (const exposure of ["codemode", "direct"]) {
  test(`hung ${exposure} server does not block prompts, discovery, or /mcp`, async () => {
    const f = fixture(exposure);
    f.handlers.get("session_start")({}, f.ctx);
    await new Promise(setImmediate);
    await new Promise(setImmediate);
    try {
      assert.equal(f.connections.length, 1);
      assert.equal(f.connections[0].state, "connecting");
      await promptly(f.handlers.get("before_agent_start")({ systemPromptOptions: { sections: {} } }, f.ctx));
      for (const toolName of ["codemode", "tool_search"]) {
        await promptly(f.handlers.get("tool_call")?.({ toolName, input: { code: 'searchTools("local tool")' } }, f.ctx));
      }
      await promptly(f.commands.get("mcp").handler("", f.ctx));
    } finally {
      await f.handlers.get("session_shutdown")({}, f.ctx);
    }
  });
}

test("connection failure updates footer without transcript warning, and shutdown clears it", async () => {
  const f = fixture();
  f.handlers.get("session_start")({}, f.ctx);
  await new Promise(setImmediate);
  await new Promise(setImmediate);
  f.connections[0].settle("failed");
  await new Promise(setImmediate);
  assert.equal(f.statuses.get("mcp"), "MCP 0/1!");
  assert.deepEqual(f.notices, []);
  f.connections[0].settle("connected");
  assert.equal(f.statuses.get("mcp"), "MCP 1/1");
  await f.handlers.get("session_shutdown")({}, f.ctx);
  assert.equal(f.statuses.get("mcp"), undefined);
});
