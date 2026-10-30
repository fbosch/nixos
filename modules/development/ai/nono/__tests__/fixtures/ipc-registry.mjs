import { defaultCapabilities, validateCapabilities } from "../../scripts/ipc-policy.mjs";

export function echoRegistry() {
  const registry = structuredClone(defaultCapabilities);
  const operation = {
    schema: {
      type: "object", properties: { workspace: { type: "string" }, message: { type: "string", format: "ipc-text", maxUtf8Bytes: 1024 } },
      required: ["workspace"], additionalProperties: false,
    },
    bindings: { workspace: "cwd" },
  };
  registry.capabilities.echo = {
    backend: "json-lines", provider: "inherited-socket", socketEnvironment: "ECHO_SOCKET",
    limits: { ...registry.capabilities["herdr-reporting"].limits },
    operations: { "echo.ping": operation, "echo.release": operation },
    cleanup: [{ id: "release", method: "echo.release", params: {} }],
  };
  registry.profiles.restricted.echo = {};
  return validateCapabilities(registry);
}
