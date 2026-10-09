import { spawnSync } from "node:child_process";
import { registerHooks } from "node:module";
import { join } from "node:path";
import { pathToFileURL } from "node:url";

const [shellModule, shell] = process.argv.slice(2);
const shellURL = pathToFileURL(shellModule).href;
// Inject only config's getBinDir; execute the pinned upstream shell helper unchanged.
const configURL = `data:text/javascript,${encodeURIComponent(`export const getBinDir = () => ${JSON.stringify(join(process.env.PI_CODING_AGENT_DIR, "bin"))};`)}`;
registerHooks({
  resolve(specifier, context, next) {
    if (specifier === "../config.js" && context.parentURL === shellURL) {
      return { url: configURL, shortCircuit: true };
    }
    return next(specifier, context);
  },
});
const { getShellEnv } = await import(shellURL);
const environment = getShellEnv();
const child = spawnSync(shell, ["-c", "command -v pi"], {
  env: environment,
  encoding: "utf8",
});
if (child.error) throw child.error;
if (child.status !== 0) throw new Error(child.stderr);
console.log(JSON.stringify({
  launchPath: process.env.PATH,
  shellPath: environment.PATH,
  pi: child.stdout.trim(),
}));
