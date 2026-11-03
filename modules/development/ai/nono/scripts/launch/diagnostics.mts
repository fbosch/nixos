import { mkdtempSync, rmSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import type { Environment, SessionStep } from "../shared/types.mts";

export async function withNonoDiagnostics<T>(environment: Environment, run: SessionStep<T>): Promise<T> {
  const directory = mkdtempSync(join(environment.TMPDIR || tmpdir(), "pi-nono-diagnostics-"));
  const path = join(directory, "nono.log");
  try {
    writeFileSync(path, "", { mode: 0o600, flag: "wx" });
    return await run({ ...environment, PI_NONO_DIAGNOSTICS_FILE: path });
  } finally {
    rmSync(directory, { recursive: true, force: true });
  }
}
