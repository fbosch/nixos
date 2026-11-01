import { randomUUID } from "node:crypto";
import { lstatSync, mkdirSync, rmSync, writeFileSync } from "node:fs";
import { join } from "node:path";
import { maxImageBytes, validatedPng } from "./desktop-png.mjs";

const chunkBytes = 32 * 1024;
const maxUploads = 4;
const maxUploadBytes = 64 * 1024 * 1024;
const maxFiles = 24;
const maxFileBytes = 128 * 1024 * 1024;
const uploadLifetimeMs = 60_000;
const fileLifetimeMs = 15 * 60_000;

export function createImageOpener(directory, launch, {setTimer = setTimeout, clearTimer = clearTimeout} = {}) {
  const uploads = new Map();
  const files = new Map();
  let reserved = 0;
  let stored = 0;
  let ready = false;
  let closed = false;

  function dropUpload(id) {
    const upload = uploads.get(id);
    if (!upload) return;
    clearTimer(upload.timer);
    reserved -= upload.total;
    uploads.delete(id);
  }
  function dropFile(path) {
    const file = files.get(path);
    if (!file) return;
    clearTimer(file.timer);
    stored -= file.bytes;
    files.delete(path);
    rmSync(path, {force:true});
  }
  function prepareDirectory() {
    if (ready) return;
    // The parent is the helper's private IPC directory, never a client-selected or shared /tmp path.
    mkdirSync(directory, {mode:0o700});
    const entry = lstatSync(directory);
    if (!entry.isDirectory() || entry.uid !== process.getuid() || (entry.mode & 0o077) !== 0) throw new Error("Unsafe desktop image directory");
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
      if (files.size >= maxFiles || stored + png.length > maxFileBytes) throw new Error("Open-image limit exceeded");
      prepareDirectory();
      const path = join(directory, `${randomUUID()}.png`);
      writeFileSync(path, png, {flag:"wx", mode:0o600});
      const file = {bytes:png.length, timer:setTimer(() => dropFile(path), fileLifetimeMs)};
      file.timer.unref?.();
      files.set(path, file);
      stored += png.length;
      try {
        await launch(path);
        return {complete:true};
      } catch (error) {
        dropFile(path);
        throw error;
      }
    },
    close() {
      if (closed) return;
      closed = true;
      for (const id of uploads.keys()) dropUpload(id);
      for (const path of files.keys()) dropFile(path);
      if (ready) rmSync(directory, {recursive:true,force:true});
    },
  };
}
