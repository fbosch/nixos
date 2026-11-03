import { createHash, randomUUID } from "node:crypto";
import { lstatSync, mkdirSync, rmSync, writeFileSync, type BigIntStats } from "node:fs";
import { join } from "node:path";
import { maxImageBytes, validatedPng } from "./png.mts";

type Timer = ReturnType<typeof setTimeout>;

interface Upload {
  total: number;
  received: number;
  chunks: Buffer[];
  timer: Timer;
}

interface StoredImage {
  path: string;
  bytes: number;
  metadata: BigIntStats;
  pending: number;
  launched: boolean;
  timer: Timer | undefined;
  /** Identity of the current expiry; a renewed lease invalidates an earlier timer callback. */
  lease: object | undefined;
}

/** One `image.open` request chunk. The capability schema fixes these types; open() rechecks every bound. */
export interface ImageChunk {
  imageId: string;
  offset: number;
  totalBytes: number;
  data: string;
}

export interface ImageOpener {
  open(chunk: ImageChunk): Promise<{ complete: boolean }>;
  close(): void;
}

export interface ImageTimers {
  setTimer?: (callback: () => void, ms: number) => Timer;
  clearTimer?: (timer: Timer | undefined) => void;
}

const chunkBytes = 32 * 1024;
const maxUploads = 4;
const maxUploadBytes = 64 * 1024 * 1024;
const maxFiles = 24;
const maxFileBytes = 128 * 1024 * 1024;
const uploadLifetimeMs = 60_000;
const fileLifetimeMs = 15 * 60_000;

export function createImageOpener(directory: string, launch: (path: string) => Promise<void>, {setTimer = setTimeout, clearTimer = clearTimeout}: ImageTimers = {}): ImageOpener {
  const uploads = new Map<string, Upload>();
  const files = new Map<string, StoredImage>();
  let reserved = 0;
  let stored = 0;
  let ready = false;
  let closed = false;

  function dropUpload(id: string): void {
    const upload = uploads.get(id);
    if (!upload) return;
    clearTimer(upload.timer);
    reserved -= upload.total;
    uploads.delete(id);
  }
  function cancelExpiry(file: StoredImage): void {
    file.lease = undefined;
    if (file.timer !== undefined) clearTimer(file.timer);
    file.timer = undefined;
  }
  function dropFile(digest: string, file: StoredImage): void {
    if (files.get(digest) !== file) return;
    cancelExpiry(file);
    stored -= file.bytes;
    files.delete(digest);
    rmSync(file.path, {force:true});
  }
  function armExpiry(digest: string, file: StoredImage): void {
    const lease = {};
    file.lease = lease;
    file.timer = setTimer(() => {
      // A canceled callback must not delete an entry after a later click has renewed it.
      if (file.lease === lease) dropFile(digest, file);
    }, fileLifetimeMs);
    file.timer.unref?.();
  }
  function unchangedFile(file: StoredImage): boolean {
    try {
      const current = lstatSync(file.path, {bigint:true});
      // The viewer may edit or replace its file; never reuse changed data or follow a replacement symlink.
      return current.isFile() && current.nlink === 1n &&
        (["dev", "ino", "size", "mtimeNs", "ctimeNs", "mode", "uid", "gid"] as const).every(key => current[key] === file.metadata[key]);
    } catch (error) {
      if ((error as NodeJS.ErrnoException).code === "ENOENT") return false;
      throw error;
    }
  }
  function prepareDirectory(): void {
    if (ready) return;
    // The parent is the helper's private IPC directory, never a client-selected or shared /tmp path.
    mkdirSync(directory, {mode:0o700});
    const entry = lstatSync(directory);
    if (!entry.isDirectory() || entry.uid !== process.getuid!() || (entry.mode & 0o077) !== 0) throw new Error("Unsafe desktop image directory");
    ready = true;
  }

  return {
    async open({imageId, offset, totalBytes, data}) {
      if (closed || typeof imageId !== "string" || !/^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/.test(imageId) ||
          !Number.isSafeInteger(offset) || offset < 0 || !Number.isSafeInteger(totalBytes) || totalBytes < 1 || totalBytes > maxImageBytes ||
          typeof data !== "string" || data.length < 4 || data.length > Math.ceil(chunkBytes / 3) * 4 || !/^[A-Za-z0-9+/]+={0,2}$/.test(data)) throw new Error("Invalid image upload");
      const bytes = Buffer.from(data, "base64");
      if (!bytes.length || bytes.length > chunkBytes || bytes.toString("base64") !== data || offset + bytes.length > totalBytes) throw new Error("Invalid image upload chunk");
      // Fixed-size intermediate chunks bound per-upload bookkeeping as well as payload bytes.
      if (offset % chunkBytes !== 0 || (offset + bytes.length < totalBytes && bytes.length !== chunkBytes)) throw new Error("Invalid image chunk boundary");
      let upload = uploads.get(imageId);
      if (!upload) {
        if (offset !== 0 || uploads.size >= maxUploads || reserved + totalBytes > maxUploadBytes) throw new Error("Image upload limit exceeded");
        upload = {total:totalBytes, received:0, chunks:[], timer:setTimer(() => dropUpload(imageId), uploadLifetimeMs)};
        upload.timer.unref?.();
        uploads.set(imageId, upload);
        reserved += totalBytes;
      }
      if (upload.total !== totalBytes || upload.received !== offset) {
        dropUpload(imageId);
        throw new Error("Image upload is out of sequence");
      }
      upload.chunks.push(bytes);
      upload.received += bytes.length;
      if (upload.received < upload.total) return {complete:false};
      dropUpload(imageId);
      const png = validatedPng(Buffer.concat(upload.chunks, upload.total));
      // Hash only the fully validated, metadata-stripped PNG, never client IDs or unvalidated uploads.
      const digest = createHash("sha256").update(png).digest("hex");
      let file: StoredImage | undefined = files.get(digest);
      if (file && !unchangedFile(file)) {
        if (file.pending > 0) throw new Error("Cached image changed while opening");
        dropFile(digest, file);
        file = undefined;
      }
      if (!file) {
        if (files.size >= maxFiles || stored + png.length > maxFileBytes) throw new Error("Open-image limit exceeded");
        prepareDirectory();
        const path = join(directory, `${randomUUID()}.png`);
        writeFileSync(path, png, {flag:"wx", mode:0o600});
        file = {path, bytes:png.length, metadata:lstatSync(path, {bigint:true}), pending:0, launched:false, timer:undefined, lease:undefined};
        files.set(digest, file);
        stored += png.length;
      }
      cancelExpiry(file);
      file.pending++;
      try {
        await launch(file.path);
        file.launched = true;
        return {complete:true};
      } finally {
        file.pending--;
        // Concurrent clicks share storage: one launch failure must not delete an image used by another launch.
        if (file.pending === 0 && files.get(digest) === file) {
          if (file.launched) armExpiry(digest, file);
          else dropFile(digest, file);
        }
      }
    },
    close() {
      if (closed) return;
      closed = true;
      for (const id of uploads.keys()) dropUpload(id);
      for (const [digest, file] of files) dropFile(digest, file);
      if (ready) rmSync(directory, {recursive:true,force:true});
    },
  };
}
