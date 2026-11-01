import assert from "node:assert/strict";
import { randomBytes, randomUUID } from "node:crypto";
import { existsSync, mkdirSync, mkdtempSync, readFileSync, readdirSync, rmSync, statSync, symlinkSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { afterEach, test } from "node:test";
import { deflateSync } from "node:zlib";
import { createImageOpener } from "../scripts/desktop-images.mjs";
import { validatedPng } from "../scripts/desktop-png.mjs";
import { chunk, png, signature } from "./fixtures/png.mjs";

const roots = [];
const openers = [];
afterEach(() => {
  for (const opener of openers.splice(0)) opener.close();
  for (const root of roots.splice(0)) rmSync(root, {recursive:true,force:true});
});
function fixture(launch = async () => {}) {
  const root = mkdtempSync(join(tmpdir(), "pi-image-store-"));
  roots.push(root);
  const directory = join(root, "images");
  const timers = new Set();
  const opener = createImageOpener(directory, launch, {
    setTimer: (fn, ms) => { const timer={fn,ms};timers.add(timer);return timer; },
    clearTimer: timer => timers.delete(timer),
  });
  openers.push(opener);
  return {root,directory,opener,timers};
}
async function upload(opener, bytes, imageId = randomUUID()) {
  let result;
  for (let offset = 0; offset < bytes.length; offset += 32768) {
    result = await opener.open({imageId,offset,totalBytes:bytes.length,data:bytes.subarray(offset,offset+32768).toString("base64")});
    assert.equal(result.complete, offset + 32768 >= bytes.length);
  }
  return result;
}

test("PNG validation checks CRC and raster length and strips metadata before opening", () => {
  const clean = png();
  assert.deepEqual(validatedPng(clean),clean);
  assert.deepEqual(validatedPng(png({ancillary:[chunk("tEXt",Buffer.from("arbitrary metadata"))]})),clean);
  const corrupt=Buffer.from(clean);corrupt[corrupt.length-1]^=1;
  for (const data of [Buffer.from("<svg/>"),Buffer.from("#!/bin/sh\n"),corrupt,clean.subarray(0,clean.length-1),Buffer.concat([clean,Buffer.from("trailing")]),png({raster:Buffer.alloc(6)}),png({raster:Buffer.alloc(4)})]) {
    assert.throws(()=>validatedPng(data));
  }
  assert.throws(()=>validatedPng(png({raster:Buffer.from([5,0,0,0,0])})),/scanline filter/);
});

test("PNG validation rejects oversized dimensions, unsupported chunks and compressed expansion", () => {
  const valid=png();
  const header=Buffer.from(valid.subarray(16,29));
  header.writeUInt32BE(9000,0);
  assert.throws(()=>validatedPng(Buffer.concat([signature,chunk("IHDR",header)])),/dimensions/);
  assert.throws(()=>validatedPng(png({ancillary:[chunk("ABCD")]})),/critical/);
  const bomb=Buffer.concat([valid.subarray(0,33),chunk("IDAT",deflateSync(Buffer.alloc(1024*1024))),chunk("IEND")]);
  assert.throws(()=>validatedPng(bomb));
  const embedded=Buffer.concat([valid.subarray(0,33),chunk("IDAT",Buffer.concat([deflateSync(Buffer.alloc(5)),Buffer.from("extra")])),chunk("IEND")]);
  assert.throws(()=>validatedPng(embedded),/raster length/);
});

test("chunked uploads are materialized privately only after validation and cleaned up", async () => {
  let opened;
  const f=fixture(async path=>{opened=path;});
  const width=200,height=200,raster=randomBytes((width*4+1)*height);
  for(let row=0;row<height;row++)raster[row*(width*4+1)]=0;
  const image=png({width,height,raster});
  assert.ok(image.length>65536);
  assert.deepEqual(await upload(f.opener,image),{complete:true});
  assert.ok(opened.startsWith(f.directory+"/"));
  assert.match(opened,/\/[0-9a-f-]+\.png$/);
  assert.deepEqual(readFileSync(opened),image);
  assert.equal(statSync(opened).mode&0o777,0o600);
  assert.equal(statSync(f.directory).mode&0o777,0o700);
  f.opener.close();
  assert.equal(existsSync(f.directory),false);
  assert.equal(f.timers.size,0);
  await assert.rejects(upload(f.opener,image),/Invalid image upload/);
});

test("malformed input and out-of-order chunks never reach the host viewer", async () => {
  let launches=0;
  const f=fixture(async()=>{launches++;});
  await assert.rejects(upload(f.opener,Buffer.from("<svg>not a PNG</svg>")),/PNG/);
  const id=randomUUID();
  const first={imageId:id,offset:0,totalBytes:65536,data:Buffer.alloc(32768).toString("base64")};
  assert.deepEqual(await f.opener.open(first),{complete:false});
  await assert.rejects(f.opener.open(first),/sequence/);
  for(const patch of [{imageId:"../../secret"},{totalBytes:33554433},{offset:1},{data:"!!!!"},{data:"YQ==\n"},{data:"Zh=="}]) {
    await assert.rejects(f.opener.open({...first,...patch}));
  }
  await assert.rejects(f.opener.open({...first,imageId:randomUUID(),data:"YQ=="}),/boundary/);
  assert.equal(launches,0);
  assert.equal(existsSync(f.directory),false);
});

test("upload budgets and deadlines bound idle allocations", async () => {
  const f=fixture();
  const data=Buffer.alloc(32768).toString("base64");
  for(let index=0;index<2;index++)await f.opener.open({imageId:randomUUID(),offset:0,totalBytes:33554432,data});
  await assert.rejects(f.opener.open({imageId:randomUUID(),offset:0,totalBytes:33554432,data}),/limit/);
  for(const timer of [...f.timers]){assert.equal(timer.ms,60000);timer.fn();}
  assert.equal(f.timers.size,0);
  for(let index=0;index<4;index++)await f.opener.open({imageId:randomUUID(),offset:0,totalBytes:65536,data});
  await assert.rejects(f.opener.open({imageId:randomUUID(),offset:0,totalBytes:65536,data}),/limit/);
});

test("viewer errors, file leases and shutdown remove owned files", async () => {
  const failing=fixture(async()=>{throw new Error("viewer failed");});
  await assert.rejects(upload(failing.opener,png()),/viewer failed/);
  assert.deepEqual(readdirSync(failing.directory),[]);
  const f=fixture();
  for(let index=0;index<24;index++)await upload(f.opener,png());
  await assert.rejects(upload(f.opener,png()),/Open-image limit/);
  for(const timer of [...f.timers]){assert.equal(timer.ms,900000);timer.fn();}
  assert.deepEqual(readdirSync(f.directory),[]);
  assert.equal(f.timers.size,0);
  await upload(f.opener,png());
});

test("an existing or symlinked image directory is not adopted", async () => {
  const f=fixture();
  const target=join(f.root,"unrelated");mkdirSync(target);
  symlinkSync(target,f.directory);
  await assert.rejects(upload(f.opener,png()));
  assert.deepEqual(readdirSync(target),[]);
});
