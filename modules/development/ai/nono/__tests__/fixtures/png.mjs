import { crc32, deflateSync } from "node:zlib";

export const signature = Buffer.from([137,80,78,71,13,10,26,10]);
export function chunk(type, data = Buffer.alloc(0)) {
  const result = Buffer.alloc(data.length + 12);
  result.writeUInt32BE(data.length, 0);
  result.write(type, 4, 4, "ascii");
  data.copy(result, 8);
  result.writeUInt32BE(crc32(result.subarray(4, result.length - 4)), result.length - 4);
  return result;
}
export function png({width = 1, height = 1, raster, ancillary = []} = {}) {
  const header = Buffer.alloc(13);
  header.writeUInt32BE(width, 0);
  header.writeUInt32BE(height, 4);
  header[8] = 8;
  header[9] = 6;
  return Buffer.concat([signature, chunk("IHDR", header), ...ancillary, chunk("IDAT", deflateSync(raster ?? Buffer.alloc((width * 4 + 1) * height))), chunk("IEND")]);
}
