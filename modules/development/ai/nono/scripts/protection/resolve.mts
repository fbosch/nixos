import { readlinkSync } from "node:fs";
import { dirname, isAbsolute, join, sep } from "node:path";
import { optionalLstat } from "../shared/paths.mts";

/**
 * Resolve `path` one component at a time, following symlinks in filesystem order:
 * normalize("link/../file") can select a different target than the kernel does.
 * A missing component ends the walk and returns the remaining components joined.
 * `onLink` sees every symlink and `onParent` every directory left through "..",
 * so callers can protect aliases and ancestors that a later replacement could redirect.
 */
export interface ResolveObserver {
  onLink?: (link: string) => void;
  onParent?: (directory: string) => void;
}

export function resolveComponents(path: string, label: string, { onLink = () => {}, onParent = () => {} }: ResolveObserver = {}): string {
  let parts = path.split(sep).filter(Boolean);
  let current: string = sep;
  let links = 0;
  while (parts.length) {
    const component = parts.shift()!;
    if (component === ".") continue;
    if (component === "..") {
      onParent(current);
      current = dirname(current);
      continue;
    }
    current = join(current, component);
    const entry = optionalLstat(current);
    if (entry === undefined) {
      if (parts.includes("..")) throw new Error(`Unresolvable ${label} parent traversal: ${path}`);
      return join(current, ...parts);
    }
    if (entry.isSymbolicLink()) {
      onLink(current);
      if (++links > 40) throw new Error(`Too many ${label} symlinks: ${path}`);
      const target = readlinkSync(current);
      parts = [...target.split(sep).filter(Boolean), ...parts];
      current = isAbsolute(target) ? sep : dirname(current);
    } else if (parts.length && !entry.isDirectory()) {
      throw new Error(`Not a ${label} directory: ${current}`);
    }
  }
  return current;
}
