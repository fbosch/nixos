import { chmodSync } from "node:fs";
import { createConnection, createServer, type Socket } from "node:net";
import type { JsonValue } from "../shared/types.mts";
import { cleanupMessages, type IpcLimits, type IpcRequest, type JsonLinesCapability, type LaunchContext, type MessageValidator } from "./policy.mts";

/** A decoded JSON-lines response object. */
export type IpcResponse = { [key: string]: JsonValue };

/**
 * Handles one validated request inside the helper process. A result is returned to the client;
 * undefined acknowledges the request without a result.
 */
export type Deliver = (request: IpcRequest) => Promise<JsonValue | undefined>;

export interface JsonLinesServerOptions {
  capability: JsonLinesCapability;
  context: LaunchContext;
  endpoint: string;
  /** Socket to forward requests to when `deliver` is absent. */
  upstream?: string;
  validate: MessageValidator;
  deliver?: Deliver;
}

export interface JsonLinesServer {
  close(): Promise<void>;
}

export function requestJsonLine(upstream: string, request: IpcRequest, limits: IpcLimits): Promise<IpcResponse> {
  return new Promise<IpcResponse>((resolve, reject) => {
    const socket = createConnection(upstream);
    let received = Buffer.alloc(0);
    const fail = (error: unknown) => { socket.destroy(); reject(error); };
    socket.setTimeout(limits.upstreamTimeoutMs, () => fail(new Error("IPC response timed out")));
    socket.once("error", fail);
    socket.once("connect", () => socket.write(JSON.stringify(request) + "\n"));
    socket.on("data", (chunk: Buffer) => {
      received = Buffer.concat([received, chunk]);
      if (received.length > limits.maxFrameBytes) return fail(new Error("IPC response is too large"));
      const newline = received.indexOf(10);
      if (newline < 0) return;
      try {
        const response = JSON.parse(new TextDecoder("utf-8", { fatal: true }).decode(received.subarray(0, newline)));
        if (response === null || typeof response !== "object" || Array.isArray(response)) throw new Error("Invalid IPC response");
        socket.destroy();
        resolve(response);
      } catch (error) { fail(error); }
    });
    socket.once("end", () => fail(new Error("IPC peer closed without acknowledging the request")));
  });
}

export async function startJsonLinesServer({ capability, context, endpoint, upstream, validate, deliver }: JsonLinesServerOptions): Promise<JsonLinesServer> {
  if (Buffer.byteLength(endpoint) > 103) throw new Error("IPC socket path exceeds the portable Unix socket limit");
  // Providers without an upstream socket handle requests in this host process and may return a result.
  const send: Deliver = deliver ?? ((request: IpcRequest) => requestJsonLine(upstream!, request, capability.limits).then((response): undefined => {
    if (response.ok !== true) throw new Error("IPC peer rejected the request");
  }));
  const cleanup = cleanupMessages(capability, context, validate);
  const { limits } = capability;
  const clients = new Set<Socket>();
  const pending = new Set<Promise<unknown>>();
  let closing = false;
  let reported = false;
  const server = createServer(client => {
    if (closing || clients.size >= limits.maxConnections) return client.destroy();
    clients.add(client);
    client.once("close", () => clients.delete(client));
    client.on("error", () => client.destroy());
    let input = Buffer.alloc(0);
    let accepted = false;
    let requestId = "pi-ipc:denied";
    const deny = () => client.end(JSON.stringify({ id: requestId, ok: false, error: { code: "PI_IPC_DENIED", message: "IPC request rejected" } }) + "\n");
    client.setTimeout(limits.clientTimeoutMs, () => client.destroy());
    client.on("data", (chunk: Buffer) => {
      if (accepted) return client.destroy();
      input = Buffer.concat([input, chunk]);
      if (input.length > limits.maxFrameBytes) { accepted = true; deny(); return; }
      const newline = input.indexOf(10);
      if (newline < 0) return;
      accepted = true;
      try {
        if (newline !== input.length - 1) throw new Error("One IPC request per connection");
        const json = new TextDecoder("utf-8", { fatal: true }).decode(input.subarray(0, newline));
        const message = JSON.parse(json);
        if (typeof message?.id === "string" && Buffer.byteLength(message.id) <= 192) requestId = message.id;
        const request = validate(message);
        const delivery = send(request).then(
          result => {
            reported = true;
            client.end(JSON.stringify(result === undefined ? { id: request.id, ok: true } : { id: request.id, ok: true, result }) + "\n");
          },
          deny,
        );
        pending.add(delivery);
        void delivery.finally(() => pending.delete(delivery));
      } catch { deny(); }
    });
  });
  await new Promise<void>((resolve, reject) => {
    server.once("error", reject);
    server.listen(endpoint, resolve);
  });
  chmodSync(endpoint, 0o600);
  return {
    async close() {
      if (closing) return;
      closing = true;
      for (const client of clients) client.destroy();
      await new Promise(resolve => server.close(resolve));
      await Promise.allSettled(pending);
      if (reported) await Promise.allSettled(cleanup.map(send));
    },
  };
}
