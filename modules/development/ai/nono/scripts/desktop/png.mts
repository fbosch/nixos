import { crc32, inflateSync, type ZlibOptions } from "node:zlib";

export const maxImageBytes = 32 * 1024 * 1024;
const maxPixels = 16 * 1024 * 1024;
const signature = Buffer.from([137, 80, 78, 71, 13, 10, 26, 10]);

export function validatedPng(input: Buffer): Buffer {
  if (!Buffer.isBuffer(input) || input.length > maxImageBytes || !input.subarray(0, 8).equals(signature)) throw new Error("Invalid PNG image");
  const chunks: Buffer[] = [signature];
  const compressed: Buffer[] = [];
  let offset = 8;
  let scanlineBytes: number | undefined;
  let height: number | undefined;
  let ended = false;
  let imageDataEnded = false;
  while (offset < input.length) {
    if (input.length - offset < 12) throw new Error("Truncated PNG chunk");
    const size = input.readUInt32BE(offset);
    const end = offset + 12 + size;
    if (end > input.length) throw new Error("Truncated PNG chunk");
    const type = input.toString("latin1", offset + 4, offset + 8);
    if (!/^[A-Za-z]{2}[A-Z][A-Za-z]$/.test(type) || crc32(input.subarray(offset + 4, end - 4)) !== input.readUInt32BE(end - 4)) throw new Error("Invalid PNG chunk");
    const data = input.subarray(offset + 8, end - 4);
    if (offset === 8 && type !== "IHDR") throw new Error("PNG header must be first");
    if (type === "IHDR") {
      if (offset !== 8 || size !== 13) throw new Error("Invalid PNG header");
      const width = data.readUInt32BE(0);
      height = data.readUInt32BE(4);
      const channels = ({0:1, 2:3, 4:2, 6:4} as Record<number, number>)[data[9]!];
      // The client re-encodes through Pi's PNG converter; only bounded, non-interlaced 8-bit rasters cross to the viewer.
      if (!width || !height || width > 8192 || height > 8192 || width * height > maxPixels || data[8] !== 8 || !channels || data[10] || data[11] || data[12]) throw new Error("Unsupported PNG dimensions or encoding");
      scanlineBytes = width * channels + 1;
      chunks.push(input.subarray(offset, end));
    } else if (type === "IDAT") {
      if (imageDataEnded) throw new Error("PNG image data must be contiguous");
      compressed.push(data);
      chunks.push(input.subarray(offset, end));
    } else if (type === "IEND") {
      if (size !== 0 || end !== input.length || compressed.length === 0) throw new Error("Invalid PNG end");
      chunks.push(input.subarray(offset, end));
      ended = true;
    } else {
      if (type[0] === type[0]!.toUpperCase()) throw new Error("Unsupported critical PNG chunk");
      if (compressed.length) imageDataEnded = true;
      // Drop ancillary metadata, including textual, colour-profile, and animation data, before host-side decoding.
    }
    offset = end;
  }
  if (!ended) throw new Error("Incomplete PNG image");
  const data = Buffer.concat(compressed);
  const expected = scanlineBytes! * height!;
  // SAFETY: with `info: true`, Node returns { buffer, engine } instead of a Buffer; @types/node does not model that overload.
  const inflated = inflateSync(data, {maxOutputLength:expected, info:true} as ZlibOptions) as unknown as { buffer: Buffer; engine: { bytesWritten: number } };
  if (inflated.buffer.length !== expected || inflated.engine.bytesWritten !== data.length) throw new Error("Invalid PNG raster length");
  for (let row = 0; row < height!; row++) if (inflated.buffer[row * scanlineBytes!]! > 4) throw new Error("Invalid PNG scanline filter");
  return Buffer.concat(chunks);
}
