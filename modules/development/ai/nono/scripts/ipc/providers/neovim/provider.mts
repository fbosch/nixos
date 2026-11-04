import * as Effect from "effect/Effect";
import { realpathSync, statSync } from "node:fs";
import { isAbsolute } from "node:path";
import { createConnection } from "node:net";
import { attach } from "neovim";
import { LaunchPrerequisiteError, attempt } from "../../../shared/errors.mts";
import type { Environment, JsonValue } from "../../../shared/types.mts";
import { createMessageValidator, type LaunchContext } from "../../policy.mts";
import type { IpcProvider } from "../../provider.mts";
import type { IpcConnection } from "../../json-lines-server.mts";

interface NeovimLaunch {
  upstream: string;
  context: LaunchContext & { launchId: string; cwd: string };
}

function scrub(environment: Environment): Environment {
  const result = { ...environment };
  for (const name of ["PI_NVIM_SOCKET", "PI_NVIM_ASK_SOCKET", "PI_NVIM_LAUNCH_ID", "NVIM", "NVIM_LISTEN_ADDRESS"]) delete result[name];
  return result;
}

function record(value: unknown): value is Record<string, JsonValue> {
  return value !== null && typeof value === "object" && !Array.isArray(value);
}

export const neovimProvider: IpcProvider = {
  start: (environment, { inherited, home, cwd, startHelper }, capability) => Effect.gen(function* () {
    const bound = scrub(environment);
    const upstream = inherited.PI_NVIM_SOCKET;
    if (!upstream) return bound;
    const launchId = inherited.PI_NVIM_LAUNCH_ID;
    if (!launchId || !/^[a-f0-9]{32}$/.test(launchId)) return yield* new LaunchPrerequisiteError({ message: "Neovim requires a valid launch identity" });
    const launch = yield* attempt((): NeovimLaunch => {
      if (!isAbsolute(upstream) || !statSync(upstream).isSocket() || statSync(upstream).uid !== process.getuid!()) throw new Error("Neovim endpoint must be an existing user-owned Unix socket");
      return { upstream: realpathSync(upstream), context: { launchId, cwd: realpathSync(cwd), home: realpathSync(home), uid: process.getuid!() } };
    });
    return yield* startHelper({ ...bound, PI_NVIM_LAUNCH_ID: launchId }, capability, launch);
  }),
  serve: (launch, capability) => {
    const { upstream, context } = launch as NeovimLaunch;
    if (!capability.persistent || capability.socketEnvironment !== "PI_NVIM_ASK_SOCKET") throw new Error("Neovim requires its persistent broker endpoint");
    const peers = new Map<IpcConnection, { close(): Promise<void>; acknowledge(payload: JsonValue): Promise<void> }>();
    const timeout = capability.limits.upstreamTimeoutMs;
    const disconnect = async (connection: IpcConnection) => {
      const peer = peers.get(connection);
      peers.delete(connection);
      await peer?.close();
    };
    return {
      context,
      validate: createMessageValidator(capability, context),
      async deliver(request, connection) {
        if (request.method === "neovim.close") { await disconnect(connection); return; }
        if (request.method === "neovim.ack") {
          const peer = peers.get(connection);
          if (!peer) throw new Error("Neovim is not bound");
          await peer.acknowledge(request.params.payload!);
          return;
        }
        if (request.method !== "neovim.bind" || peers.has(connection)) throw new Error("Invalid Neovim operation");
        // Recheck identity independently of the configurable operation schemas.
        if (request.params.launchId !== context.launchId || request.params.cwd !== context.cwd || typeof request.params.sessionId !== "string") throw new Error("Neovim launch mismatch");
        const socket = createConnection(upstream);
        socket.on("error", () => connection.close());
        // neovim 5.4.0 initializes a silent logger by replacing console methods. Keep helper errors visible.
        const originalConsole = { ...console };
        const nvim = attach({ reader: socket, writer: socket });
        Object.assign(console, originalConsole);
        let closed = false;
        let channelId: number | undefined;
        let binding: Record<string, JsonValue> | undefined;
        const deadline = async <T,>(work: Promise<T>): Promise<T> => {
          let timer: ReturnType<typeof setTimeout> | undefined;
          let failed: (() => void) | undefined;
          try {
            return await Promise.race([work, new Promise<never>((_, reject) => {
              failed = () => reject(new Error("Neovim RPC disconnected"));
              if (socket.destroyed) failed();
              else socket.once("close", failed);
              timer = setTimeout(() => { socket.destroy(); reject(new Error("Neovim RPC timed out")); }, timeout);
            })]);
          } finally {
            clearTimeout(timer);
            if (failed) socket.off("close", failed);
          }
        };
        const close = async () => {
          if (closed) return;
          closed = true;
          try {
            if (channelId !== undefined && !socket.destroyed) await deadline(nvim.lua("return _G.__piAsk.close(...)", [channelId, context.launchId]));
          } finally { if (!socket.destroyed) await nvim.close(); }
        };
        peers.set(connection, {
          close,
          async acknowledge(payload) {
            if (!binding || !record(payload) || payload.launchId !== binding.launchId || payload.sessionId !== binding.sessionId || payload.ownerId !== binding.ownerId) throw new Error("Neovim acknowledgement identity mismatch");
            if (await deadline(nvim.lua("return _G.__piAsk.acknowledge(...)", [channelId!, context.launchId, payload])) !== true) throw new Error("Neovim rejected acknowledgement");
          },
        });
        nvim.on("disconnect", () => { if (!closed) connection.close(); });
        nvim.on("notification", (method: string, args: unknown[]) => {
          if (closed) return;
          if (method === "pi:nvim-close/v1") { connection.close(); return; }
          if (method !== "pi:nvim-prompt/v1" || args.length !== 1 || !record(args[0])) return;
          const prompt = args[0];
          // Prompt identity is chosen by the editor, never by an agent acknowledgement.
          if (prompt.launchId !== context.launchId || prompt.cwd !== context.cwd || prompt.sessionId !== request.params.sessionId || (binding && (prompt.ownerId !== binding.ownerId || prompt.editorPid !== binding.editorPid))) { connection.close(); return; }
          if (!connection.notify("neovim.prompt", prompt)) connection.close();
        });
        try {
          channelId = await deadline(nvim.channelId);
          const result: unknown = await deadline(nvim.lua("return _G.__piAsk.bind(...)", [channelId, context.launchId, context.cwd, request.params.sessionId]));
          if (!record(result) || Object.keys(result).sort().join(",") !== "channelId,cwd,editorPid,launchId,ownerId,sessionId,version"
            || result.version !== 1 || result.channelId !== channelId || result.launchId !== context.launchId || result.cwd !== context.cwd
            || result.sessionId !== request.params.sessionId || typeof result.ownerId !== "string" || result.ownerId.length === 0 || result.ownerId.length > 128
            || typeof result.editorPid !== "number" || !Number.isSafeInteger(result.editorPid) || result.editorPid < 1) throw new Error("Invalid Neovim binding");
          binding = result;
          return result;
        } catch (error) { await disconnect(connection); throw error; }
      },
      disconnect,
      async dispose() { await Promise.allSettled([...peers.keys()].map(disconnect)); },
    };
  },
  scrub,
};
