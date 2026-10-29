import assert from "node:assert/strict";
import { createRequire, syncBuiltinESMExports } from "node:module";
import { join } from "node:path";
import { test } from "node:test";
import { pathToFileURL } from "node:url";

const packageRoot = process.env.PI_TEST_PACKAGE;
assert.ok(packageRoot, "PI_TEST_PACKAGE must point to the installed Pi package");

// Count resize workers through the live builtin binding that image-resize.js imports.
const workerThreads = createRequire(import.meta.url)("node:worker_threads");
const BaseWorker = workerThreads.Worker;
let workersStarted = 0;
workerThreads.Worker = class extends BaseWorker {
  constructor(...args) {
    workersStarted++;
    super(...args);
  }
};
syncBuiltinESMExports();

const load = (path) => import(pathToFileURL(join(packageRoot, "dist", path)).href);
const { resizeImage } = await load("utils/image-resize.js");
const { resizeImageInProcess } = await load("utils/image-resize-core.js");
const { loadPhoton } = await load("utils/photon.js");
const photon = await loadPhoton();
assert.ok(photon, "Photon must load");

function noise(width, height) {
  const pixels = new Uint8Array(width * height * 4);
  let seed = 7;
  for (let index = 0; index < pixels.length; index++) {
    seed = (seed * 1103515245 + 12345) >>> 0;
    pixels[index] = index % 4 === 3 ? 255 : seed >>> 24;
  }
  return new photon.PhotonImage(pixels, width, height);
}

function encode(width, height, format) {
  const image = noise(width, height);
  try {
    if (format === "png") return Buffer.from(image.get_bytes());
    if (format === "webp") return Buffer.from(image.get_bytes_webp());
    return Buffer.from(image.get_bytes_jpeg(80));
  } finally {
    image.free();
  }
}

// EXIF APP1 segment carrying orientation 6 (rotate 90° clockwise), inserted after SOI.
function withOrientation6(jpeg) {
  const tiff = Buffer.from("49492a0008000000010012010300010000000600000000000000", "hex");
  const payload = Buffer.concat([Buffer.from("Exif\0\0"), tiff]);
  const segment = Buffer.alloc(payload.length + 4);
  segment[0] = 0xff;
  segment[1] = 0xe1;
  segment.writeUInt16BE(payload.length + 2, 2);
  segment.set(payload, 4);
  return Buffer.concat([jpeg.subarray(0, 2), segment, jpeg.subarray(2)]);
}

const GIF_1X1 = Buffer.from("47494638396101000100800000000000ffffff2c00000000010001000002024401003b", "hex");

async function resizeCountingWorkers(bytes, mimeType, options) {
  const before = workersStarted;
  const result = await resizeImage(bytes, mimeType, options);
  return { result, workers: workersStarted - before };
}

test("images within the limits pass through without a worker and match a full decode", async () => {
  const fixtures = [
    ["image/png", encode(40, 30, "png")],
    ["image/jpeg", encode(40, 30, "jpeg")],
    ["image/webp", encode(40, 30, "webp")],
    ["image/gif", GIF_1X1],
  ];
  for (const [mimeType, bytes] of fixtures) {
    const { result, workers } = await resizeCountingWorkers(bytes, mimeType);
    assert.equal(workers, 0, mimeType);
    assert.deepEqual(result, await resizeImageInProcess(bytes, mimeType), mimeType);
    assert.equal(result.wasResized, false, mimeType);
  }
});

test("EXIF-rotated and truncated images still decode in the worker", async () => {
  const rotated = withOrientation6(encode(40, 30, "jpeg"));
  const rotation = await resizeCountingWorkers(rotated, "image/jpeg");
  assert.equal(rotation.workers, 1);
  assert.deepEqual([rotation.result.width, rotation.result.height], [30, 40]);

  const png = encode(40, 30, "png");
  const truncated = png.subarray(0, png.length - 12);
  const partial = await resizeCountingWorkers(truncated, "image/png");
  assert.equal(partial.workers, 1);
  assert.deepEqual(partial.result, await resizeImageInProcess(truncated, "image/png"));
});

test("resizing returns the first encoding that fits, PNG before JPEG", async () => {
  const source = noise(64, 64);
  const resized = photon.resize(source, 32, 32, photon.SamplingFilter.Lanczos3);
  const png = Buffer.from(resized.get_bytes()).toString("base64");
  const jpeg = Buffer.from(resized.get_bytes_jpeg(80)).toString("base64");
  resized.free();
  const bytes = Buffer.from(source.get_bytes());
  source.free();
  assert.ok(jpeg.length < png.length, "noise must compress better as JPEG");

  const limits = { maxWidth: 32, maxHeight: 32 };
  const pngResult = await resizeImage(bytes, "image/png", { ...limits, maxBytes: png.length + 1 });
  assert.equal(pngResult.mimeType, "image/png");
  assert.equal(pngResult.data, png);

  const jpegResult = await resizeImage(bytes, "image/png", { ...limits, maxBytes: jpeg.length + 1 });
  assert.equal(jpegResult.mimeType, "image/jpeg");
  assert.equal(jpegResult.data, jpeg);
  assert.deepEqual([jpegResult.width, jpegResult.height, jpegResult.wasResized], [32, 32, true]);
});
