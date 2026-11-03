/** A process environment as the launcher passes it around: unset variables are absent or undefined. */
export type Environment = Record<string, string | undefined>;

/** How a sandboxed Pi process ended; spawnSync results and credential-proxy runs share this shape. */
export interface ExitResult {
  status: number | null;
  signal: NodeJS.Signals | null;
  error?: Error;
}

/** Parsed JSON before a caller has checked its shape. */
export type JsonValue = string | number | boolean | null | JsonValue[] | JsonObject;
export type JsonObject = { [key: string]: JsonValue };

/** A nono profile path: a plain path, or a path limited to one platform (`linux` or `macos`). */
export type ProfilePath = string | { path: string; when?: string };

/** The parts of a nono profile (`profile.json` plus generated fields) that the launcher reads. */
export interface NonoProfile {
  filesystem?: {
    allow?: ProfilePath[];
    read?: ProfilePath[];
    write?: ProfilePath[];
    allow_file?: ProfilePath[];
    write_file?: ProfilePath[];
    unix_socket?: ProfilePath[];
    bypass_protection?: ProfilePath[];
    [key: string]: unknown;
  };
  linux?: { af_unix_mediation?: string; sandbox_policy?: string };
  network?: {
    credentials?: string[];
    custom_credentials?: Record<string, { env_var?: unknown; [key: string]: unknown }>;
    tls_intercept?: { ca_env_vars?: string[] };
    [key: string]: unknown;
  };
  unsafe_macos_seatbelt_rules?: string[];
  [key: string]: unknown;
}

/** Node's `fs` errors carry a `code`; other thrown values are narrowed by the caller. */
export type ErrnoError = NodeJS.ErrnoException;
