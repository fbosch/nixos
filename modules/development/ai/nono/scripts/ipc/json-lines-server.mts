import { chmodSync } from "node:fs";
import { createConnection, createServer, type Socket } from "node:net";
import type { JsonValue } from "../shared/types.mts";
import { cleanupMessages, createNotificationValidator, type IpcLimits, type IpcRequest, type JsonLinesCapability, type LaunchContext, type MessageValidator } from "./policy.mts";

export type IpcResponse = { [key: string]: JsonValue };

export interface IpcConnection {
  /** Queued behind the current response, so a bind result always precedes its notifications. */
  notify(method: string, params: unknown): boolean;
  close(): void;
}

export type Deliver = (request: IpcRequest) => Promise<JsonValue | undefined>;
export type ConnectionDeliver = (request: IpcRequest, connection: IpcConnection) => Promise<JsonValue | undefined>;
export type Disconnect = (connection: IpcConnection) => Promise<void> | void;

export interface JsonLinesServerOptions {
  capability: JsonLinesCapability;
  context: LaunchContext;
  endpoint: string;
  upstream?: string;
  validate: MessageValidator;
  deliver?: ConnectionDeliver;
  disconnect?: Disconnect;
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

export async function startJsonLinesServer({ capability, context, endpoint, upstream, validate, deliver, disconnect }: JsonLinesServerOptions): Promise<JsonLinesServer> {
  if (Buffer.byteLength(endpoint) > 103) throw new Error("IPC socket path exceeds the portable Unix socket limit");
  if (capability.persistent && !deliver) throw new Error("Persistent IPC requires a host provider");
  const send: ConnectionDeliver = deliver ?? ((request) => requestJsonLine(upstream!, request, capability.limits).then((response): undefined => {
    if (response.ok !== true) throw new Error("IPC peer rejected the request");
  }));
  const validateNotification = createNotificationValidator(capability);
  const cleanup = cleanupMessages(capability, context, validate);
  const { limits } = capability;
  const clients = new Set<Socket>();
  const pending = new Set<Promise<unknown>>();
  let closing = false;
  let reported = false;
  const server = createServer(client => {
    if (closing || clients.size >= limits.maxConnections) return client.destroy();
    clients.add(client);
    let input = Buffer.alloc(0);
    let processing = false;
    let stopped = false;
    let active: Promise<unknown> = Promise.resolve();
    let notifications: string[] = [];
    let notificationBytes = 0;
    let requestId: string | number = "pi-ipc:denied";
    const write = (frame: string) => {
      if (stopped || client.destroyed || client.writableLength + Buffer.byteLength(frame) > limits.maxFrameBytes * 2) return false;
      client.write(frame);
      return true;
    };
    const connection: IpcConnection = {
      notify(method, params) {
        if (!capability.persistent || stopped || client.destroyed || !validateNotification(method, params)) return false;
        const frame = JSON.stringify({ method, params }) + "\n";
        if (Buffer.byteLength(frame) > limits.maxFrameBytes) return false;
        if (!processing) return write(frame);
        if (notificationBytes + Buffer.byteLength(frame) > limits.maxFrameBytes) return false;
        notifications.push(frame);
        notificationBytes += Buffer.byteLength(frame);
        return true;
      },
      close: () => client.destroy(),
    };
    const deny = () => {
      if (stopped) return;
      stopped = true;
      client.end(JSON.stringify({ id: requestId, ok: false, error: { code: "PI_IPC_DENIED", message: "IPC request rejected" } }) + "\n");
    };
    client.once("close", () => {
      stopped = true;
      // A disconnect during bind must retire the binding after the in-flight RPC settles.
      const cleanupTask = active.then(() => disconnect?.(connection)).catch(() => {}).finally(() => {
        clients.delete(client);
        pending.delete(cleanupTask);
      });
      pending.add(cleanupTask);
    });
    client.on("error", () => client.destroy());
    client.setTimeout(limits.clientTimeoutMs, () => client.destroy());
    const consume = () => {
      if (processing || stopped || client.destroyed) return;
      const newline = input.indexOf(10);
      if (newline < 0) { if (input.length > limits.maxFrameBytes) deny(); return; }
      if (newline === 0 || newline > limits.maxFrameBytes) return deny();
      const frame = input.subarray(0, newline);
      input = input.subarray(newline + 1);
      if (!capability.persistent && input.length !== 0) return deny();
      processing = true;
      try {
        const message = JSON.parse(new TextDecoder("utf-8", { fatal: true }).decode(frame));
        if (typeof message?.id === "string" && Buffer.byteLength(message.id) <= 192) requestId = message.id;
        else if (typeof message?.id === "number" && Number.isSafeInteger(message.id)) requestId = message.id;
        const request = validate(message);
        active = Promise.resolve().then(() => send(request, connection)).then(result => {
          reported = true;
          const response = JSON.stringify(result === undefined ? { id: request.id, ok: true } : { id: request.id, ok: true, result }) + "\n";
          if (Buffer.byteLength(response) > limits.maxFrameBytes) return client.destroy();
          if (!write(response)) return client.destroy();
          if (!capability.persistent) { stopped = true; client.end(); return; }
          for (const notification of notifications) if (!write(notification)) return client.destroy();
          notifications = [];
          notificationBytes = 0;
          processing = false;
          client.setTimeout(input.length ? limits.clientTimeoutMs : 0);
          consume();
        }).catch(deny);
        const task = active;
        pending.add(task);
        void task.finally(() => pending.delete(task));
      } catch { deny(); }
    };
    client.on("data", (chunk: Buffer) => {
      if (stopped) return;
      // Retain the single-request contract even if a second frame arrives during delivery.
      if (!capability.persistent && processing) return client.destroy();
      input = Buffer.concat([input, chunk]);
      if (input.length > limits.maxFrameBytes * 2) return deny();
      client.setTimeout(limits.clientTimeoutMs);
      consume();
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
      await new Promise<void>(resolve => server.close(() => resolve()));
      await Promise.allSettled(pending);
      if (reported) await Promise.allSettled(cleanup.map(request => send(request, { notify: () => false, close() {} })));
    },
  };
}
