import assert from "node:assert/strict";
import { spawnSync } from "node:child_process";
import { mkdirSync, mkdtempSync, readFileSync, realpathSync, rmSync, symlinkSync, writeFileSync } from "node:fs";
import { once } from "node:events";
import { createServer } from "node:net";
import { dirname, join } from "node:path";
import { afterEach, test } from "node:test";
import { launchArguments, referenceApprovalStore } from "../scripts/launcher.mjs";
import { prepareAgentRuntime } from "../scripts/agent-protection.mjs";
import { prepareSandboxRuntime } from "../scripts/sandbox-runtime.mjs";

const roots = [];
const envBinary = process.env.ENV_TEST_BINARY || "/usr/bin/env";
const profileSource = JSON.parse(readFileSync(new URL("../scripts/profile.json", import.meta.url), "utf8"));
function repository(path) {
  const common = join(path, ".git");
  for (const name of ["objects", "refs"]) mkdirSync(join(common, name), { recursive: true });
  writeFileSync(join(common, "HEAD"), "ref: refs/heads/main\n");
  return common;
}
function fixture() {
  const root = realpathSync(mkdtempSync(join(process.cwd(), ".pi-edit-scope-")));
  roots.push(root);
  const home = join(root, "home");
  const dotfiles = join(home, "dotfiles");
  const nixos = join(home, "nixos");
  const project = join(home, "project");
  const agent = join(dotfiles, ".pi", "agent");
  const defaultAgent = join(home, ".pi", "agent");
  for (const directory of [dotfiles, nixos, project]) repository(directory);
  for (const directory of [agent, defaultAgent, join(root, "tmp")]) mkdirSync(directory, { recursive: true });
  prepareAgentRuntime(agent);
  prepareSandboxRuntime(home);
  for (const name of ["instructions", "extensions"]) mkdirSync(join(agent, name));
  writeFileSync(join(agent, "instructions", "codemode.md"), "original instructions");
  writeFileSync(join(agent, "extensions", "fixture.mjs"), "export default () => {};\n");
  writeFileSync(join(agent, "settings.json"), JSON.stringify({references:{
    dotfiles:{path:dotfiles,description:"Configuration"},nixos:{path:nixos,description:"System configuration"},
  }}));
  for (const name of ["instructions", "extensions", "settings.json"]) symlinkSync(join(agent, name), join(defaultAgent, name));
  const profile = join(root, "profile.json");
  writeFileSync(profile, JSON.stringify({...profileSource,network:{block:true},linux:{...profileSource.linux,af_unix_mediation:"pathname"}}));
  const environment = {HOME:home,PATH:process.env.PATH,TMPDIR:join(root,"tmp"),XDG_CACHE_HOME:join(home,".cache"),XDG_STATE_HOME:join(root,"state")};
  const args = cwd => launchArguments(cwd, agent, home, environment, profile, process.execPath, envBinary);
  const worktree = (checkout, name) => {
    const path = join(root, "worktrees", name);
    const metadata = join(checkout, ".git", "worktrees", name);
    mkdirSync(path, {recursive:true});
    mkdirSync(metadata, {recursive:true});
    writeFileSync(join(path, ".git"), `gitdir: ${metadata}\n`);
    writeFileSync(join(metadata, "commondir"), "../..\n");
    writeFileSync(join(metadata, "gitdir"), `${join(path, ".git")}\n`);
    return {path,metadata};
  };
  return {root,home,dotfiles,nixos,project,agent,defaultAgent,profile,environment,args,worktree};
}
afterEach(() => { for (const root of roots.splice(0)) rmSync(root, {recursive:true,force:true}); });
const values = (args, flag) => args.flatMap((value, index) => value === flag ? [args[index + 1]] : []);
const covers = (root, path) => path === root || path.startsWith(`${root}/`);
function canWriteInstructions(args, agent) {
  const directory = join(agent, "instructions");
  return values(args, "--allow").some(root => covers(root, directory));
}

for (const name of ["dotfiles", "nixos"]) {
  test(`${name} and its subdirectories permit Pi setup edits`, () => {
    const f = fixture();
    const nested = join(f[name], "src");
    mkdirSync(nested);
    for (const cwd of [f[name], nested]) {
      const args = f.args(cwd);
      assert.ok(canWriteInstructions(args, f.agent));
      assert.ok(values(args, "--allow").some(root => covers(root, f.defaultAgent)));
    }
  });
  test(`registered ${name} worktrees and their aliases permit Pi setup edits`, () => {
    const f = fixture();
    const {path} = f.worktree(f[name], `${name}-branch`);
    const nested = join(path, "src");
    const alias = join(f.root, "alias");
    mkdirSync(nested);
    symlinkSync(path, alias);
    for (const cwd of [path, nested, alias]) assert.ok(canWriteInstructions(f.args(cwd), f.agent));
  });
}

test("unrelated repositories, lookalikes, and their worktrees retain Pi lockdown", () => {
  const f = fixture();
  const lookalike = join(f.home, "dotfiles-other");
  repository(lookalike);
  const {path} = f.worktree(f.project, "project-branch");
  for (const cwd of [f.project, lookalike, path]) assert.equal(canWriteInstructions(f.args(cwd), f.agent), false);
});

test("a forged worktree pointer cannot select another checkout's editing scope", () => {
  const f = fixture();
  const {metadata} = f.worktree(f.dotfiles, "registered");
  const forged = join(f.root, "forged");
  mkdirSync(forged);
  writeFileSync(join(forged, ".git"), `gitdir: ${metadata}\n`);
  assert.throws(() => f.args(forged), /registration does not match this checkout/);
});

test("editing scope cannot turn the home directory into a writable Pi directory", () => {
  const f = fixture();
  assert.throws(() => launchArguments(f.dotfiles, f.home, f.home, f.environment, f.profile, process.execPath, envBinary), /home|ancestor|credential|SSH/);
});

for (const scenario of ["dotfiles", "nixos", "worktree", "unrelated"]) {
  test(`fresh sandbox ${scenario}: atomic Pi edits follow launch scope and other protections remain`, {
    skip:process.platform !== "linux" || !process.env.NONO_TEST_BINARY,
    timeout:30000,
  }, async t => {
    const f = fixture();
    const cwd = scenario === "worktree" ? f.worktree(f.dotfiles, "edit").path : scenario === "unrelated" ? f.project : f[scenario];
    const editable = scenario !== "unrelated";
    const fish = join(f.dotfiles, ".config", "fish", "config.fish");
    for (const directory of [dirname(fish), join(f.home,".config","fish"), join(f.home,".claude"), dirname(referenceApprovalStore(f.home))]) mkdirSync(directory,{recursive:true});
    writeFileSync(fish,"# host shell\n");
    symlinkSync(fish,join(f.home,".config","fish","config.fish"));
    writeFileSync(join(f.home,".claude",".credentials.json"),"synthetic credential");
    writeFileSync(referenceApprovalStore(f.home),"[]",{mode:0o600});
    mkdirSync(join(f.home, ".ssh"));
    writeFileSync(join(f.home, ".ssh", "id_ed25519"), "synthetic private key");
    const socket = join(f.root, "ssh-agent.sock");
    const server = createServer(connection => connection.end());
    server.listen(socket);
    await once(server, "listening");
    t.after(() => new Promise(resolve => server.close(resolve)));
    f.environment.SSH_AUTH_SOCK = socket;
    const args = f.args(cwd);
    if (!args.includes("--allow-cwd")) {
      const policy = JSON.parse(readFileSync(f.profile,"utf8"));
      policy.workdir = {access:"none"};
      writeFileSync(f.profile,JSON.stringify(policy));
    }
    const script = `
      const assert = require("node:assert/strict"), fs = require("node:fs"), path = require("node:path"), net = require("node:net");
      const [agent, defaultAgent, configRoot, home, approvals, editing, socket] = process.argv.slice(1);
      const denied = e => ["EACCES","EPERM"].includes(e.code);
      const atomicEdit = (target, value) => {
        target = fs.realpathSync(target);
        const temporary = path.join(path.dirname(target), ".atomic-edit-probe");
        fs.writeFileSync(temporary, value, {flag:"wx"});
        fs.renameSync(temporary, target);
        assert.equal(fs.readFileSync(target,"utf8"), value);
      };
      const edits = [
        [path.join(defaultAgent,"instructions","codemode.md"),"edited instructions"],
        [path.join(agent,"settings.json"),"{}"],
        [path.join(defaultAgent,"extensions","fixture.mjs"),"export default () => {}; // edited\\n"],
      ];
      // A chdir after confinement must not upgrade an unrelated session.
      process.chdir(configRoot);
      for (const [target,value] of edits) {
        if (editing === "yes") atomicEdit(target,value);
        else assert.throws(() => atomicEdit(target,value),denied);
      }
      const newExtension = path.join(agent, "extensions", "new-extension");
      if (editing === "yes") fs.mkdirSync(newExtension);
      else assert.throws(() => fs.mkdirSync(newExtension), denied);
      assert.throws(() => fs.readFileSync(path.join(home,".ssh","id_ed25519")),denied);
      assert.throws(() => fs.readFileSync(path.join(home,".claude",".credentials.json")),denied);
      assert.throws(() => fs.appendFileSync(path.join(home,".config","fish","config.fish"),"p"),denied);
      assert.throws(() => fs.appendFileSync(approvals,"p"),denied);
      const endpoints = [...[22,80,443].map(port=>({host:"127.0.0.1",port})), {path:socket}];
      Promise.all(endpoints.map(endpoint => new Promise(resolve => {
        const socket=net.connect(endpoint);
        const finish=code=>{socket.destroy();resolve(code);};
        socket.once("connect",()=>finish("connected"));socket.once("error",e=>finish(e.code));socket.setTimeout(2000,()=>finish("timeout"));
      }))).then(codes=>{for(const code of codes)assert.ok(["EACCES","EPERM"].includes(code),code);console.log("scope and retained denials passed");}).catch(e=>{console.error(e);process.exitCode=1;});
    `;
    const child = spawnSync(process.env.NONO_TEST_BINARY,[...args,"-e",script,f.agent,f.defaultAgent,f.dotfiles,f.home,referenceApprovalStore(f.home),editable?"yes":"no",socket],{
      cwd,env:f.environment,encoding:"utf8",timeout:20000,
    });
    assert.ifError(child.error);
    assert.equal(child.status,0,child.stdout+child.stderr);
    assert.match(child.stdout,/scope and retained denials passed/);
  });
}
