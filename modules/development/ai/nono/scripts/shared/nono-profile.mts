import { readFileSync } from "node:fs";
import { isAbsolute } from "node:path";
import { InvalidConfigError, LaunchPrerequisiteError } from "./errors.mts";
import { existingFile } from "./paths.mts";
import type { NonoProfile } from "./types.mts";

/**
 * The Nix-generated nono profile, read and shape-checked the same way by every module that uses
 * it. nono validates the full schema itself; this checks only the fields the launcher edits.
 */
export function readNonoProfile(path: string): NonoProfile {
  if (!isAbsolute(path) || !existingFile(path)) throw new LaunchPrerequisiteError({ message: `Nix nono profile missing: ${path}` });
  let profile: unknown;
  try {
    profile = JSON.parse(readFileSync(path, "utf8"));
  } catch (cause) {
    throw new InvalidConfigError({ message: "Nix nono profile is not valid JSON", cause });
  }
  if (!profile || typeof profile !== "object" || Array.isArray(profile)) throw new InvalidConfigError({ message: "Invalid Pi nono profile." });
  const { filesystem, unsafe_macos_seatbelt_rules: rules } = profile as NonoProfile;
  if (filesystem !== undefined && (!filesystem || typeof filesystem !== "object" || Array.isArray(filesystem))) {
    throw new InvalidConfigError({ message: "Invalid Pi nono filesystem profile." });
  }
  if ((filesystem?.read !== undefined && !Array.isArray(filesystem.read)) ||
      (rules !== undefined && (!Array.isArray(rules) || !rules.every((rule) => typeof rule === "string")))) {
    throw new InvalidConfigError({ message: "Invalid Pi nono profile rule lists." });
  }
  return profile as NonoProfile;
}
