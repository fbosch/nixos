import assert from "node:assert/strict";
import { randomBytes, randomUUID } from "node:crypto";
import { existsSync, linkSync, mkdirSync, mkdtempSync, readFileSync, readdirSync, rmSync, statSync, symlinkSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { afterEach, test } from "node:test";
import { deflateSync } from "node:zlib";
import { createImageOpener } from "../scripts/ipc/providers/desktop/images.mts";
import { validatedPng } from "../scripts/ipc/providers/desktop/png.mts";
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

test("repeated validated images reuse one private file and refresh inactivity expiry", async () => {
  const opened=[];
  const f=fixture(async path=>{opened.push(path);});
  const image=png();
  await upload(f.opener,image);
  const firstLease=[...f.timers][0];
  const firstMetadata=statSync(opened[0]);
  for(let index=0;index<30;index++)await upload(f.opener,image);
  assert.equal(new Set(opened).size,1);
  assert.equal(readdirSync(f.directory).length,1);
  assert.equal(statSync(opened[0]).ino,firstMetadata.ino,"cache hits do not rewrite the file");
  assert.equal(f.timers.size,1);
  assert.ok(!f.timers.has(firstLease),"reuse replaces the old lease");
  firstLease.fn();
  assert.equal(existsSync(opened[0]),true,"a stale expiry callback cannot remove a reused file");
  [...f.timers][0].fn();
  assert.equal(existsSync(opened[0]),false);
  assert.equal(f.timers.size,0);
  await upload(f.opener,image);
  assert.notEqual(opened.at(-1),opened[0],"an expired file is recreated with a fresh private name");
  firstLease.fn();
  assert.equal(existsSync(opened.at(-1)),true,"old callbacks cannot delete the replacement entry");
});

test("the cache key uses validated PNG bytes rather than upload IDs or discarded metadata", async () => {
  const opened=[];
  const f=fixture(async path=>{opened.push(path);});
  const id=randomUUID();
  await upload(f.opener,png(),id);
  await upload(f.opener,png({ancillary:[chunk("tEXt",Buffer.from("different metadata"))]}));
  assert.equal(opened[0],opened[1]);
  await upload(f.opener,png({raster:Buffer.from([0,1,2,3,255])}),id);
  assert.notEqual(opened[0],opened[2],"reusing a client ID cannot select a cached image");
  const invalid=Buffer.from(png());invalid[invalid.length-1]^=1;
  await assert.rejects(upload(f.opener,invalid,id));
  assert.equal(opened.length,3,"a prior cache hit cannot bypass validation");
});

test("concurrent clicks share storage and an unsuccessful launch cannot remove a successful peer's image", async () => {
  const launches=[];
  const f=fixture(path=>new Promise((resolve,reject)=>launches.push({path,resolve,reject})));
  const first=upload(f.opener,png());
  const second=upload(f.opener,png());
  assert.equal(launches.length,2);
  assert.equal(launches[0].path,launches[1].path);
  assert.equal(readdirSync(f.directory).length,1);
  launches[1].resolve();
  await second;
  launches[0].reject(new Error("first viewer failed"));
  await assert.rejects(first,/first viewer failed/);
  assert.ok(existsSync(launches[1].path));
  assert.equal(f.timers.size,1);
});

test("failed opens clean up unused entries without discarding previously opened images", async () => {
  const opened=[];
  let fail=true;
  const f=fixture(async path=>{opened.push(path);if(fail)throw new Error("viewer failed");});
  await assert.rejects(upload(f.opener,png()),/viewer failed/);
  assert.deepEqual(readdirSync(f.directory),[]);
  fail=false;
  await upload(f.opener,png());
  assert.notEqual(opened[0],opened[1]);
  fail=true;
  await assert.rejects(upload(f.opener,png()),/viewer failed/);
  assert.equal(opened[1],opened[2]);
  assert.ok(existsSync(opened[1]));
});

test("cache contents are private to each broker instance", async () => {
  const paths=[];
  const first=fixture(async path=>{paths.push(path);});
  const second=fixture(async path=>{paths.push(path);});
  await upload(first.opener,png());
  await upload(second.opener,png());
  assert.notEqual(paths[0],paths[1]);
  first.opener.close();
  assert.ok(existsSync(paths[1]));
});

for (const change of ["deleted", "modified", "symlinked", "hard-linked"]) {
  test(`${change} cached files are not reused`, async () => {
    const opened=[];
    const f=fixture(async path=>{opened.push(path);});
    const image=png();
    await upload(f.opener,image);
    const first=opened[0];
    const external=join(f.root,"external");
    if(change==="deleted") rmSync(first);
    if(change==="modified") writeFileSync(first,"changed");
    if(change==="symlinked") {
      writeFileSync(external,"private external data");
      rmSync(first);
      symlinkSync(external,first);
    }
    if(change==="hard-linked") linkSync(first,external);
    await upload(f.opener,image);
    assert.notEqual(opened[1],first);
    assert.equal(existsSync(first),false);
    assert.deepEqual(readFileSync(opened[1]),image);
    assert.equal(statSync(opened[1]).nlink,1);
    assert.equal(readdirSync(f.directory).length,1);
    if(change==="symlinked") assert.equal(readFileSync(external,"utf8"),"private external data");
    if(change==="hard-linked") assert.deepEqual(readFileSync(external),image);
  });
}

test("in-flight reuse prevents expiry and shutdown cannot rearm the cache", async () => {
  let resolve;
  let pause=false;
  const opened=[];
  const f=fixture(path=>{
    opened.push(path);
    return pause ? new Promise(done=>{resolve=done;}) : Promise.resolve();
  });
  await upload(f.opener,png());
  const oldLease=[...f.timers][0];
  pause=true;
  const pending=upload(f.opener,png());
  oldLease.fn();
  assert.equal(opened[0],opened[1]);
  assert.ok(existsSync(opened[0]));
  assert.equal(f.timers.size,0,"in-flight opens hold the file instead of racing an expiry timer");
  f.opener.close();
  resolve();
  await pending;
  assert.equal(existsSync(f.directory),false);
  assert.equal(f.timers.size,0,"shutdown cannot leave a late timer or cache entry");
});

test("viewer errors, file leases and shutdown remove owned files", async () => {
  const failing=fixture(async()=>{throw new Error("viewer failed");});
  await assert.rejects(upload(failing.opener,png()),/viewer failed/);
  assert.deepEqual(readdirSync(failing.directory),[]);
  const f=fixture();
  const uniqueImage = index => png({raster:Buffer.from([0,index,0,0,255])});
  for(let index=0;index<24;index++)await upload(f.opener,uniqueImage(index));
  await upload(f.opener,uniqueImage(0));
  assert.equal(readdirSync(f.directory).length,24,"a cache hit is allowed when all unique-file slots are occupied");
  await assert.rejects(upload(f.opener,uniqueImage(24)),/Open-image limit/);
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
