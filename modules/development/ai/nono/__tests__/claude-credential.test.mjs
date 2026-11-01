import assert from "node:assert/strict";
import { spawnSync } from "node:child_process";
import { chmodSync, linkSync, mkdirSync, mkdtempSync, readFileSync, rmSync, symlinkSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { afterEach, test } from "node:test";
import { fileURLToPath } from "node:url";
import { captureClaudeAccessToken } from "../scripts/claude-credential.mjs";

const roots = [];
const now = 2_000_000_000_000;
const access = "synthetic-claude-access-token";
const refresh = "synthetic-claude-refresh-token";
const helper = fileURLToPath(new URL("../scripts/claude-credential.mjs", import.meta.url));
function fixture(overrides = {}) {
  const home = mkdtempSync(join(tmpdir(), "pi-claude-capture-"));
  roots.push(home);
  const directory = join(home, ".claude");
  mkdirSync(directory, {mode:0o700});
  const path = join(directory, ".credentials.json");
  const record = {claudeAiOauth:{accessToken:access,refreshToken:refresh,expiresAt:now+3_600_000,scopes:["user:inference"],...overrides}};
  writeFileSync(path, JSON.stringify(record), {mode:0o600});
  return {home,directory,path,record};
}
afterEach(() => { for(const root of roots.splice(0)) rmSync(root,{recursive:true,force:true}); });

test("capture returns only the access token and leaves CLI-managed refresh data unchanged", () => {
  const f=fixture();
  const original=readFileSync(f.path,"utf8");
  assert.equal(captureClaudeAccessToken(f.home,now),access);
  assert.equal(readFileSync(f.path,"utf8"),original);
  writeFileSync(f.path,JSON.stringify({...f.record,claudeAiOauth:{...f.record.claudeAiOauth,accessToken:"rotated-synthetic-access-token"}}));
  assert.equal(captureClaudeAccessToken(f.home,now),"rotated-synthetic-access-token");
});

for(const expiresAt of [now-1,now,now+60_000]) {
  test(`expired or near-expiry credentials fail closed (${expiresAt-now} ms)`, () => {
    const f=fixture({expiresAt});
    assert.throws(()=>captureClaudeAccessToken(f.home,now),/expired or near expiry/);
  });
}
for(const overrides of [
  {accessToken:""},{accessToken:"token\r\nInjected: header"},{accessToken:"x".repeat(8193)},
  {expiresAt:"tomorrow"},{scopes:["user:profile"]},{accessToken:{secret:access}},
]) {
  test(`invalid credential metadata is rejected (${Object.keys(overrides).join()})`, () => {
    const f=fixture(overrides);
    assert.throws(()=>captureClaudeAccessToken(f.home,now),/invalid or unsafe/);
  });
}

test("unsafe credential ownership, permissions, links, and oversized files are rejected", t => {
  const f=fixture();
  chmodSync(f.path,0o644);
  assert.throws(()=>captureClaudeAccessToken(f.home,now),/invalid or unsafe/);
  chmodSync(f.path,0o600);
  chmodSync(f.directory,0o777);
  assert.throws(()=>captureClaudeAccessToken(f.home,now),/invalid or unsafe/);
  chmodSync(f.directory,0o700);
  const alias=join(f.home,"alias");
  linkSync(f.path,alias);
  assert.throws(()=>captureClaudeAccessToken(f.home,now),/invalid or unsafe/);
  rmSync(alias);
  const uid=process.getuid();
  const mock=t.mock.method(process,"getuid",()=>uid+1);
  assert.throws(()=>captureClaudeAccessToken(f.home,now),/invalid or unsafe/);
  mock.mock.restore();
  writeFileSync(f.path,"x".repeat(65537));
  assert.throws(()=>captureClaudeAccessToken(f.home,now),/invalid or unsafe/);
  rmSync(f.path);
  writeFileSync(alias,JSON.stringify(f.record),{mode:0o600});
  symlinkSync(alias,f.path);
  assert.throws(()=>captureClaudeAccessToken(f.home,now),/invalid or unsafe/);
});

test("helper stdout is token-only and malformed source errors do not echo credentials", () => {
  const f=fixture({expiresAt:Date.now()+3_600_000});
  const run=()=>spawnSync(process.execPath,[helper],{env:{HOME:f.home},encoding:"utf8",timeout:5000});
  const good=run();
  assert.equal(good.status,0,good.stderr);
  assert.equal(good.stdout,access);
  assert.equal(good.stderr,"");
  writeFileSync(f.path,`invalid ${access} ${refresh}`);
  const malformed=run();
  assert.equal(malformed.status,1);
  assert.equal(malformed.stdout,"");
  assert.match(malformed.stderr,/invalid or unsafe/);
  assert.ok(!malformed.stderr.includes(access));
  assert.ok(!malformed.stderr.includes(refresh));
  rmSync(f.path);
  const missing=run();
  assert.equal(missing.status,1);
  assert.equal(missing.stdout,"");
  assert.match(missing.stderr,/log in with Claude on the host/);
});
