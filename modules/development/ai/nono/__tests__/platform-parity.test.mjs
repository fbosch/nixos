import * as Effect from "effect/Effect";
import assert from "node:assert/strict";
import { spawnSync } from "node:child_process";
import { existsSync, mkdirSync, mkdtempSync, readFileSync, realpathSync, rmSync, symlinkSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { dirname, join } from "node:path";
import { afterEach, test } from "node:test";
import { fileURLToPath } from "node:url";
import { agentProtection, prepareAgentRuntime } from "../scripts/protection/agent.mts";
import { withProtectedShellProfile } from "../scripts/protection/shell.mts";

const roots = [];
const envBinary = process.env.ENV_TEST_BINARY || "/usr/bin/env";
const base = JSON.parse(readFileSync(new URL("../scripts/profile.json", import.meta.url), "utf8"));
function fixture() {
  const root = realpathSync(mkdtempSync(join(tmpdir(), "pi-parity-")));
  roots.push(root);
  const home = join(root, "home");
  const config = join(home, "dotfiles");
  const agent = join(config, ".pi", "agent");
  const defaultAgent = join(home, ".pi", "agent");
  const work = join(home, "project");
  for (const path of [agent, defaultAgent, work, join(root, "tmp"), join(root, "runtime"), join(agent, "extensions"), join(config, ".config", "fish")]) mkdirSync(path, {recursive:true});
  writeFileSync(join(agent, "settings.json"), "{}");
  writeFileSync(join(agent, "auth.json"), "{}");
  writeFileSync(join(agent, "extensions", "existing.mjs"), "export default () => {};\n");
  symlinkSync(join(agent, "settings.json"), join(defaultAgent, "settings.json"));
  symlinkSync(join(agent, "extensions"), join(defaultAgent, "extensions"));
  const profile = join(root, "profile.json");
  // Synthetic HOME is under /tmp; do not let a temporary read grant cover its credential stores.
  writeFileSync(profile, JSON.stringify({...base, filesystem:{...base.filesystem,read:base.filesystem.read.filter(path=>path!=="/tmp")}, network:{block:true}, linux:{...base.linux, af_unix_mediation:"pathname"}}));
  const environment = {
    HOME:home, PATH:process.env.PATH, TMPDIR:join(root,"tmp"),
    XDG_RUNTIME_DIR:join(root,"runtime"), XDG_STATE_HOME:join(root,"state"),
    PI_CODING_AGENT_DIR:agent, PI_MODEL_EXECUTOR:"0", PI_NONO_DIAGNOSTICS:"0", NO_COLOR:"1",
  };
  return {root,home,config,agent,defaultAgent,work,profile,environment};
}
afterEach(() => { for (const root of roots.splice(0)) rmSync(root, {recursive:true,force:true}); });

for (const editable of [false, true]) {
  test(`Darwin bootstrap ${editable ? "configuration" : "unrelated"} session passes the selected agent policy into Seatbelt`, () => {
    const f = fixture();
    const nono = join(f.root, "nono-fixture");
    writeFileSync(nono, `#!${process.execPath}
const fs=require("node:fs");
const args=process.argv.slice(2);
const profile=args[args.indexOf("--profile")+1];
console.log(JSON.stringify({args,profile,policy:JSON.parse(fs.readFileSync(profile,"utf8"))}));
`, {mode:0o700});
    const launcher = fileURLToPath(new URL("../scripts/launcher.mts", import.meta.url));
    // Exercise the actual bootstrap and generated-profile lifetime; this does not emulate kernel enforcement.
    const driver = `
      Object.defineProperty(process,"platform",{value:"darwin"});
      process.argv=[process.execPath,...process.argv.slice(1)];
      await import((await import("node:url")).pathToFileURL(process.argv[1]).href);
    `;
    const child = spawnSync(process.execPath,["--input-type=module","-e",driver,launcher,nono,process.execPath,f.profile,"/missing-direnv",envBinary,"--version"],{
      cwd:editable?f.config:f.work,env:f.environment,encoding:"utf8",timeout:15000,
    });
    assert.ifError(child.error);
    assert.equal(child.status,0,child.stderr);
    const result = JSON.parse(child.stdout);
    const deny = result.policy.unsafe_macos_seatbelt_rules.at(-1);
    assert.match(deny,/^\(deny file-write\*/);
    assert.ok(deny.includes(`(subpath ${JSON.stringify(join(f.config,".config","fish"))})`));
    assert.ok(deny.includes(`(subpath ${JSON.stringify(join(f.home,".local","state","pi-sandbox"))})`));
    for (const path of [join(f.agent,"settings.json"),join(f.agent,"extensions")]) {
      assert.equal(deny.includes(`(subpath ${JSON.stringify(path)})`),!editable,path);
    }
    for (const name of ["sessions","cache","session-history","tasks","auth-profiles","fff"]) {
      assert.ok(existsSync(join(f.agent,name)),name);
      assert.equal(deny.includes(`(subpath ${JSON.stringify(join(f.agent,name))})`),false,name);
    }
    assert.ok(result.args.includes("--trust-proxy-ca"));
    assert.ok(result.args.includes("JITI_FS_CACHE=false"));
    assert.ok(result.args.includes(`PI_LOCKFILE_DIR=${join(f.home,".cache","pi","locks")}`));
    assert.equal(existsSync(result.profile),false,"generated policy is removed after the child exits");
    assert.equal(JSON.parse(readFileSync(f.profile,"utf8")).unsafe_macos_seatbelt_rules.length,base.unsafe_macos_seatbelt_rules.length);
  });
}

test("Seatbelt protects linked and missing controls without blocking mutable agent data", () => {
  const f = fixture();
  prepareAgentRuntime(f.agent);
  const library = join(f.home,".cache","linked-library");
  mkdirSync(library,{recursive:true});
  writeFileSync(join(library,"index.mjs"),"export default {};\n");
  symlinkSync(library,join(f.agent,"extensions","linked"));
  const future = join(f.home,"future","extension.mjs");
  symlinkSync(future,join(f.agent,"extensions","future.mjs"));
  const controls = Effect.runSync(agentProtection(f.home,f.agent,f.environment,base,"darwin"));
  assert.ok(controls.protectedPaths.includes(library));
  assert.ok(controls.protectedPaths.includes(future));
  withProtectedShellProfile(f.profile,f.home,f.environment,path=>{
    const policy=JSON.parse(readFileSync(path,"utf8"));
    const deny=policy.unsafe_macos_seatbelt_rules.at(-1);
    for(const path of [library,future,join(f.agent,"extensions")]) assert.ok(deny.includes(`(subpath ${JSON.stringify(path)})`),path);
    assert.ok(deny.includes(`(literal ${JSON.stringify(dirname(future))})`),"ancestor replacement is denied");
    for(const path of controls.runtimePaths) assert.equal(deny.includes(`(subpath ${JSON.stringify(path)})`),false,path);
    assert.equal(deny.includes(`(subpath ${JSON.stringify(join(f.agent,"auth.json"))})`),false);
  },"darwin",controls.protectedPaths);
});

test("protected control names cannot inject Seatbelt expressions", () => {
  const f = fixture();
  const path = join(f.agent, "extensions", 'hostile") (allow default)\n');
  writeFileSync(path, "fixture");
  assert.throws(() => withProtectedShellProfile(f.profile, f.home, f.environment, () => assert.fail("must not launch"), "darwin", [path]), /control character/);
});
