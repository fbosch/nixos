import type { Confinement } from "./confinement.mts";
import { linuxConfinement } from "./linux.mts";
import { macosConfinement } from "./macos.mts";

/** The confinement for `platform`. nono supports only Linux and macOS. */
export function confinementFor(platform: NodeJS.Platform): Confinement {
  return platform === "darwin" ? macosConfinement : linuxConfinement;
}
