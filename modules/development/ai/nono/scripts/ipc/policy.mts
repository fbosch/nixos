import { Ajv, type AnySchemaObject, type ValidateFunction } from "ajv";
import { readFileSync, lstatSync, realpathSync, type Stats } from "node:fs";
import { join } from "node:path";
import type { JsonValue } from "../shared/types.mts";
import { grant, type Grant } from "../shared/grant-plan.mts";

// Types mirror capabilities.schema.json; Ajv validates every manifest against it before use.

/** A closed JSON Schema object for one operation's `params`. */
export interface OperationSchema {
  type: "object";
  additionalProperties: false;
  properties?: Record<string, JsonValue>;
  required?: string[];
  [key: string]: JsonValue | undefined;
}

export interface Operation {
  schema: OperationSchema;
  /** Maps a `params` field to the launch-context key whose captured value it must equal. */
  bindings: Record<string, string>;
}

export interface CleanupMessage {
  id: string;
  method: string;
  params: Record<string, JsonValue>;
  optionalBindings?: string[];
}

export interface IpcLimits {
  maxFrameBytes: number;
  maxConnections: number;
  clientTimeoutMs: number;
  upstreamTimeoutMs: number;
}

export interface EndpointCapability {
  backend: "endpoint";
  discovery: "selected-git-metadata";
  filename: string;
  authority: "full-protocol";
}

export interface JsonLinesCapability {
  backend: "json-lines";
  limits: IpcLimits;
  operations: Record<string, Operation>;
  cleanup: CleanupMessage[];
  provider: "herdr" | "inherited-socket" | "desktop";
  socketEnvironment: string;
}

export type Capability = EndpointCapability | JsonLinesCapability;

/** Per-profile options. Endpoint capabilities must choose an access mode and platforms. */
export interface SelectionOptions {
  access?: "connect-existing" | "bind";
  platforms?: NodeJS.Platform[];
}

export interface CapabilityRegistry {
  version: 1;
  capabilities: Record<string, Capability>;
  profiles: Record<string, Record<string, SelectionOptions>> & { ordinary: Record<string, SelectionOptions>; restricted: Record<string, SelectionOptions> };
}

export type SelectedCapability = (EndpointCapability & SelectionOptions) | (JsonLinesCapability & SelectionOptions);
export type SelectedCapabilities = Record<string, SelectedCapability>;

/** Launch-time values that bound request fields must match. */
export type LaunchContext = Record<string, JsonValue | undefined>;

/** A request accepted by createMessageValidator; `params` matched the operation schema. */
export interface IpcRequest {
  id: string | number;
  method: string;
  params: Record<string, JsonValue>;
}

/** Validates an untrusted decoded frame; typed as IpcRequest because only `method` is read before schema validation. */
export type MessageValidator = (value: IpcRequest) => IpcRequest;

const ajv = new Ajv({ strict: true, strictRequired: false, allErrors: false });
ajv.addFormat("ipc-text", (value: string) => value.isWellFormed() && !/[\x00-\x1f\x7f-\x9f]/u.test(value));
ajv.addKeyword({
  keyword: "maxUtf8Bytes", type: "string", schemaType: "number",
  metaSchema: { type: "integer", minimum: 0, maximum: 65536 },
  validate: (limit: number, value: string) => Buffer.byteLength(value) <= limit,
});
function readJson(path: URL): AnySchemaObject {
  try { return JSON.parse(readFileSync(path, "utf8")); }
  catch (cause) { throw new Error(`Cannot read IPC JSON: ${path}`, { cause }); }
}
const manifestSchema = readJson(new URL("./capabilities.schema.json", import.meta.url));
const validateManifest = ajv.compile(manifestSchema);
const compiled = new WeakMap<JsonLinesCapability, Map<string, ValidateFunction>>();
const identifier = { anyOf: [
  { type: "string", format: "ipc-text", maxUtf8Bytes: 192 },
  { type: "integer", minimum: -Number.MAX_SAFE_INTEGER, maximum: Number.MAX_SAFE_INTEGER },
] };

function validators(capability: JsonLinesCapability): Map<string, ValidateFunction> {
  if (compiled.has(capability)) return compiled.get(capability)!;
  const result = new Map<string, ValidateFunction>();
  for (const [method, operation] of Object.entries(capability.operations)) {
    if (operation.schema.type !== "object" || operation.schema.additionalProperties !== false) {
      throw new Error(`IPC operation ${method} must use a closed object schema`);
    }
    for (const field of Object.keys(operation.bindings)) {
      if (!Object.hasOwn(operation.schema.properties ?? {}, field)) throw new Error(`IPC binding has no schema property: ${field}`);
    }
    result.set(method, ajv.compile({
      type: "object", properties: { id: identifier, method: { const: method }, params: operation.schema },
      required: ["id", "method", "params"], additionalProperties: false,
    }));
  }
  compiled.set(capability, result);
  return result;
}

function freeze<T>(value: T): T {
  if (value && typeof value === "object") {
    for (const child of Object.values(value)) freeze(child);
    Object.freeze(value);
  }
  return value;
}

// SAFETY: every field is read only after validateManifest accepted the value against
// capabilities.schema.json, which the types above mirror.
export function validateCapabilities(value: CapabilityRegistry): CapabilityRegistry {
  if (!validateManifest(value)) throw new Error(`Invalid IPC capability manifest: ${ajv.errorsText(validateManifest.errors)}`);
  for (const [profile, selections] of Object.entries(value.profiles)) {
    const variables = new Set<string>();
    for (const [name, options] of Object.entries(selections)) {
      if (!Object.hasOwn(value.capabilities, name)) throw new Error(`Unknown IPC capability in ${profile}: ${name}`);
      const capability = value.capabilities[name]!;
      const endpoint = capability.backend === "endpoint";
      if (endpoint !== Object.hasOwn(options, "access")) throw new Error(`Invalid IPC selection for ${name}`);
      if (!endpoint) {
        if (variables.has((capability as JsonLinesCapability).socketEnvironment)) throw new Error(`Duplicate IPC socket export: ${(capability as JsonLinesCapability).socketEnvironment}`);
        variables.add((capability as JsonLinesCapability).socketEnvironment);
      }
    }
  }
  for (const capability of Object.values(value.capabilities)) {
    if (capability.backend !== "json-lines") continue;
    if (capability.provider === "herdr" && capability.socketEnvironment !== "HERDR_SOCKET_PATH") throw new Error("The Herdr provider requires HERDR_SOCKET_PATH");
    validators(capability);
    for (const cleanup of capability.cleanup) {
      if (!Object.hasOwn(capability.operations, cleanup.method)) throw new Error(`Unknown IPC cleanup operation: ${cleanup.method}`);
      for (const field of cleanup.optionalBindings ?? []) {
        if (!Object.hasOwn(capability.operations[cleanup.method]!.bindings, field)) throw new Error(`Unknown IPC cleanup binding: ${field}`);
      }
    }
  }
  return freeze(value);
}

export function loadCapabilities(path: string | URL = new URL("./capabilities.json", import.meta.url)): CapabilityRegistry {
  let value: CapabilityRegistry;
  try { value = JSON.parse(readFileSync(path, "utf8")); }
  catch (cause) { throw new Error(`Cannot read IPC capability manifest: ${path}`, { cause }); }
  return validateCapabilities(value);
}

export const defaultCapabilities = loadCapabilities();

export function selectCapabilities(registry: CapabilityRegistry, profile: string, platform: NodeJS.Platform = process.platform): SelectedCapabilities {
  if (!Object.hasOwn(registry.profiles, profile)) throw new Error(`Unknown IPC profile: ${profile}`);
  return Object.fromEntries(Object.entries(registry.profiles[profile]!).flatMap(([name, options]): [string, SelectedCapability][] => {
    if (options.platforms && !options.platforms.includes(platform)) return [];
    return [[name, Object.freeze({ ...registry.capabilities[name]!, ...options })]];
  }));
}

export function endpointGrants(capabilities: SelectedCapabilities, locations: Record<string, string[]>): Grant[] {
  const grants: Grant[] = [];
  for (const capability of Object.values(capabilities)) {
    if (capability.backend !== "endpoint") continue;
    const roots = locations[capability.discovery];
    if (!roots) throw new Error(`Missing IPC endpoint discovery: ${capability.discovery}`);
    for (const root of new Set(roots)) {
      const endpoint = join(realpathSync(root), capability.filename);
      let entry: Stats | undefined;
      try { entry = lstatSync(endpoint); }
      catch (error) { if ((error as NodeJS.ErrnoException).code !== "ENOENT") throw error; }
      if (entry && (!entry.isSocket() || entry.uid !== process.getuid!() || entry.nlink !== 1)) {
        if (capability.access === "bind") throw new Error(`Unsafe IPC endpoint: ${endpoint}`);
        continue;
      }
      if (capability.access === "bind") grants.push(grant("--allow-unix-socket-bind", endpoint));
      else if (entry) grants.push(grant("--allow-unix-socket", endpoint));
    }
  }
  return grants;
}

export function createMessageValidator(capability: JsonLinesCapability, context: LaunchContext): MessageValidator {
  const operations = validators(capability);
  const captured = structuredClone(context);
  for (const operation of Object.values(capability.operations)) {
    for (const field of operation.schema.required ?? []) {
      const binding = operation.bindings[field];
      if (binding && (!Object.hasOwn(captured, binding) || captured[binding] === undefined)) throw new Error(`Missing IPC launch binding: ${binding}`);
    }
  }
  // SAFETY: only `method` is read before the operation schema validates the whole message.
  return (value: IpcRequest) => {
    if (!value || typeof value !== "object" || !operations.has(value.method) || !operations.get(value.method)!(value)) {
      throw new Error("IPC request does not match an allowed operation schema");
    }
    for (const [field, binding] of Object.entries(capability.operations[value.method]!.bindings)) {
      if (!Object.hasOwn(value.params, field)) continue;
      if (!Object.hasOwn(captured, binding) || captured[binding] === undefined || value.params[field] !== captured[binding]) throw new Error(`IPC launch identity mismatch: ${field}`);
    }
    return structuredClone(value);
  };
}

export function cleanupMessages(capability: JsonLinesCapability, context: LaunchContext, validate: MessageValidator): IpcRequest[] {
  return capability.cleanup.map(cleanup => {
    const operation = capability.operations[cleanup.method]!;
    const params = structuredClone(cleanup.params);
    for (const field of [...(operation.schema.required ?? []), ...(cleanup.optionalBindings ?? [])]) {
      const binding = operation.bindings[field];
      if (binding && Object.hasOwn(context, binding) && context[binding] !== undefined) params[field] = context[binding]!;
    }
    return validate({ id: cleanup.id, method: cleanup.method, params });
  });
}
