import { providerSession } from "../../scripts/ipc/session.mts";

/** A provider session with the real filter helper; `inherited` is the launcher's environment. */
export function session(inherited, home, { cwd = "/", agentDir = "/", args = [] } = {}) {
  return providerSession({ inherited, home, cwd, agentDir, args });
}
