import assert from "node:assert/strict";
import { test } from "node:test";
import { configurePiPaths, hostOnlyVariables, sessionEnvironment } from "../scripts/launch/environment.mts";
import { MODEL_EXECUTOR_SOCKET } from "../scripts/model-executor/launch.mts";

const home = "/home/user";
const project = Object.fromEntries(hostOnlyVariables.map((name) => [name, `/project/${name}`]));

test("a project .envrc cannot set any host-only variable", () => {
  const host = { PATH: "/bin", HOME: home, PI_NVIM_ASK_SOCKET: "/run/user/1/nvim/pi-ask.sock", TMPDIR: "/tmp/host" };
  const session = sessionEnvironment(host, { ...host, ...project, PROJECT_ONLY: "kept" }, home, "linux");
  for (const name of hostOnlyVariables) {
    assert.equal(session[name], host[name], name);
    if (host[name] === undefined) assert.ok(!Object.hasOwn(session, name), `${name} must be removed, not set to undefined`);
  }
  assert.equal(session.PROJECT_ONLY, "kept");
});

test("socket endpoints chosen by a project never reach the session", () => {
  const session = sessionEnvironment({ HOME: home }, { HOME: home, PI_NVIM_ASK_SOCKET: "/run/user/1/bus", SSH_AUTH_SOCK: "/var/run/docker.sock", HERDR_SOCKET_PATH: "/run/podman/podman.sock" }, home, "linux");
  for (const name of ["PI_NVIM_ASK_SOCKET", "SSH_AUTH_SOCK", "HERDR_SOCKET_PATH"]) assert.equal(session[name], undefined, name);
});

test("only the launcher selects the model executor socket", () => {
  const host = { HOME: home, [MODEL_EXECUTOR_SOCKET]: "/inherited/executor.sock" };
  assert.equal(sessionEnvironment(host, { ...host, [MODEL_EXECUTOR_SOCKET]: "/project/executor.sock" }, home, "linux")[MODEL_EXECUTOR_SOCKET], undefined);
});

test("the SSH agent reaches the session only after the host opts in", () => {
  const socket = "/run/user/1/ssh-agent.sock";
  const optedOut = sessionEnvironment({ HOME: home, SSH_AUTH_SOCK: socket }, { HOME: home, SSH_AUTH_SOCK: socket, PI_NONO_SSH_AGENT: "1" }, home, "linux");
  assert.equal(optedOut.SSH_AUTH_SOCK, undefined);
  assert.equal(optedOut.PI_NONO_SSH_AGENT, undefined);
  const optedIn = sessionEnvironment({ HOME: home, SSH_AUTH_SOCK: socket, PI_NONO_SSH_AGENT: "1" }, { HOME: home, SSH_AUTH_SOCK: "/project/agent.sock" }, home, "linux");
  assert.equal(optedIn.SSH_AUTH_SOCK, socket);
  assert.equal(optedIn.PI_NONO_SSH_AGENT, "1");
});

test("packaged SSH precedes project OpenSSH while Pi keeps its immutable entry first", () => {
  const host = { HOME: home, PATH: "/host/bin", PI_SSH_BIN: "/nix/store/pi/share/pi/ssh-bin" };
  const session = sessionEnvironment(host, { ...host, PATH: "/project/openssh/bin", PI_SSH_BIN: "/project/ssh-bin" }, home, "linux");
  configurePiPaths(session, home, "/nix/store/pi/bin");
  assert.deepEqual(session.PATH.split(":"), ["/nix/store/pi/bin", host.PI_SSH_BIN, "/project/openssh/bin", `${home}/.pi/agent/bin`]);
});

test("macOS gets a runtime directory below the host TMPDIR, never a project one", () => {
  const host = { HOME: home, TMPDIR: "/var/folders/host/T/" };
  const session = sessionEnvironment(host, { ...host, TMPDIR: "/project/tmp", XDG_RUNTIME_DIR: "/project/runtime" }, home, "darwin");
  assert.equal(session.TMPDIR, host.TMPDIR);
  assert.equal(session.XDG_RUNTIME_DIR, host.TMPDIR);
  assert.equal(sessionEnvironment(host, host, home, "linux").XDG_RUNTIME_DIR, undefined);
});

test("project values that do not select grants stay available to Pi", () => {
  const host = { HOME: home, XDG_CONFIG_HOME: "/home/user/.config" };
  const session = sessionEnvironment(host, { ...host, XDG_CONFIG_HOME: "/project/config", DEVENV_ROOT: "/project" }, home, "linux");
  assert.equal(session.XDG_CONFIG_HOME, "/project/config");
  assert.equal(session.DEVENV_ROOT, "/project");
});
