import assert from "node:assert/strict";
import { spawnSync } from "node:child_process";
import { appendFileSync, chmodSync, linkSync, mkdirSync, readFileSync, renameSync, rmSync, symlinkSync, truncateSync, unlinkSync, writeFileSync } from "node:fs";
import { dirname, join } from "node:path";

const [home, profile] = process.argv.slice(2);
const source = join(home, "dotfiles", ".config", "fish");
const config = join(home, ".config", "fish");
const target = join(source, "config.fish");
const alias = join(config, "config.fish");
const replacement = join(home, "replacement");
writeFileSync(replacement, "replacement fixture");

function denied(operation) {
  assert.throws(operation, (error) => error.code === "EPERM" || error.code === "EACCES");
}

for (const path of [target, alias, join(home, ".shinit"), join(home, "dotfiles", ".shinit"), join(home, ".cache", "fish", "atuin-init.fish")]) {
  const before = readFileSync(path, "utf8");
  denied(() => writeFileSync(path, "overwrite"));
  denied(() => appendFileSync(path, "append"));
  denied(() => truncateSync(path, 0));
  denied(() => chmodSync(path, 0o777));
  denied(() => unlinkSync(path));
  denied(() => renameSync(replacement, path));
  denied(() => renameSync(path, join(home, "moved-startup")));
  assert.equal(readFileSync(path, "utf8"), before);
}

denied(() => writeFileSync(profile, "changed policy"));
denied(() => unlinkSync(profile));
denied(() => renameSync(replacement, profile));

for (const path of [source, config, dirname(source), join(home, "dotfiles"), dirname(config), dirname(dirname(profile))]) {
  denied(() => renameSync(path, `${path}-moved`));
}
for (const path of [join(source, "new.fish"), join(config, "new.fish"), join(home, ".cache", "fish", "new.fish"), join(home, ".config", "starship.toml")]) {
  denied(() => writeFileSync(path, "new startup"));
  denied(() => symlinkSync(replacement, path));
}
denied(() => mkdirSync(join(source, "conf.d")));

const hardlink = join(home, "startup-hardlink");
let linked = false;
try {
  linkSync(target, hardlink);
  linked = true;
} catch (error) {
  assert.ok(error.code === "EPERM" || error.code === "EACCES", error.message);
}
if (linked) denied(() => writeFileSync(hardlink, "hardlink overwrite"));
assert.equal(readFileSync(target, "utf8"), "# startup fixture\n");

const inherited = spawnSync(process.execPath, ["--input-type=module", "-e", `
  import assert from 'node:assert/strict';
  import {writeFileSync} from 'node:fs';
  assert.throws(() => writeFileSync(process.argv[1], 'nested raw command'), e => e.code === 'EPERM' || e.code === 'EACCES');
`, alias], { encoding: "utf8" });
assert.equal(inherited.status, 0, inherited.stderr);

for (const directory of [join(home, "dotfiles"), join(home, ".config"), join(home, ".cache")]) {
  const ordinary = join(directory, "ordinary.txt");
  const temporary = `${ordinary}.tmp`;
  writeFileSync(ordinary, "first");
  writeFileSync(temporary, "atomic edit");
  renameSync(temporary, ordinary);
  assert.equal(readFileSync(ordinary, "utf8"), "atomic edit");
  rmSync(ordinary);
}
