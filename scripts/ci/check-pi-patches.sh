#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
source_dir="${1:-/nix/store/0anj9nrq9msg2h82s6d0176bfd2k4wg0-pi-src-with-lock}"
auth_patch="$repo_root/modules/development/ai/pi/pi-auth-profiles-startup.patch"
selector_patch="$repo_root/modules/development/ai/pi/pi-selector-overlays.patch"
work_dir="$(mktemp -d)"
trap 'rm -rf -- "$work_dir"' EXIT

if [[ ! -d $source_dir ]]; then
  printf 'Pi source directory not found: %s\n' "$source_dir" >&2
  exit 1
fi

patched_dir="$work_dir/pi"
mkdir -p "$patched_dir"
cp -a "$source_dir"/. "$patched_dir"/
chmod -R u+w "$patched_dir"

apply_patch() {
  local patch_path="$1"
  patch --batch --fuzz=0 -p1 -d "$patched_dir" <"$patch_path"
}

# Keep patch ordering explicit: selectors are validated against the auth-startup port.
patch --batch --dry-run --fuzz=0 -p1 -d "$patched_dir" <"$auth_patch" >/dev/null
patch --batch --dry-run --fuzz=0 -p1 -d "$patched_dir" <"$selector_patch" >/dev/null
apply_patch "$auth_patch" >/dev/null
apply_patch "$selector_patch" >/dev/null
if find "$patched_dir" -name '*.rej' -o -name '*.orig' | grep -q .; then
  printf 'Patch application left reject/original files\n' >&2
  exit 1
fi

# Ensure this slice did not accidentally drop unrelated 0.87 lifecycle and cache APIs.
required_bindings=(
  'dist/core/agent-session-services.js|pendingNativeProviderRegistrations'
  'dist/core/agent-session-services.js|refreshOnCreate: false'
  'dist/core/agent-session-services.js|await modelRuntime.refresh({ allowNetwork: false })'
  'dist/core/extensions/runner.d.ts|CacheWarmingDecisionEvent'
  'dist/core/extensions/runner.d.ts|ContextWithSystemEvent'
  'dist/core/extensions/runner.d.ts|TurnEndEvent'
  'dist/core/session-manager.js|const entry = JSON.parse(line)'
  'dist/core/session-manager.js|Plain custom entries are display/state entries'
  'dist/core/session-manager.js|if (entry.type === "custom_message")'
  'dist/core/settings-manager.js|CACHE_WARMING_MODES'
  'dist/core/settings-manager.js|DEFAULT_COMPACTION_TOKEN_SETTINGS'
  'dist/modes/interactive/components/settings-selector.js|CACHE_WARMING_MODES'
  'dist/modes/interactive/interactive-mode.js|formatCacheWarmingStatus'
  'dist/modes/interactive/interactive-mode.js|isRetryableAssistantError'
)
for binding in "${required_bindings[@]}"; do
  file="${binding%%|*}"
  needle="${binding#*|}"
  grep -Fq -- "$needle" "$patched_dir/$file" || {
    printf 'Missing upstream binding: %s (%s)\n' "$file" "$needle" >&2
    exit 1
  }
done
if grep -Fq 'openai_checkpoint' "$auth_patch" || grep -Fq 'openai_checkpoint' "$selector_patch"; then
  printf 'Native OpenAI checkpoint workflow leaked into this slice\n' >&2
  exit 1
fi

python3 - "$patched_dir" <<'PY'
import sys
from pathlib import Path

root = Path(sys.argv[1])
services = (root / "dist/core/agent-session-services.js").read_text()
before = services.index("await startupRunner.emitBeforeModelAvailability")
refresh = services.index("await modelRuntime.refresh({ allowNetwork: false })")
assert before < refresh, "auth availability hook must precede model refresh"
assert "refreshOnCreate: false" in services, "create-time refresh must remain deferred"
PY

# Exercise the new settings behavior without network access. These tiny module stubs
# live only in the temporary copy because the pinned source has no dependency tree.
mkdir -p "$patched_dir/node_modules/@earendil-works/pi-ai" \
  "$patched_dir/node_modules/proper-lockfile" \
  "$patched_dir/node_modules/undici" \
  "$patched_dir/node_modules/cross-spawn"
printf '{"type":"module","main":"index.js","exports":"./index.js"}\n' >"$patched_dir/node_modules/@earendil-works/pi-ai/package.json"
printf 'export const DEFAULT_MAX_AGENT_RETRY_DELAY_MS = 60000; export function getCurrentSystemMessage(messages) { return messages[0]; }\n' >"$patched_dir/node_modules/@earendil-works/pi-ai/index.js"
printf '{"type":"module","main":"index.js","exports":"./index.js"}\n' >"$patched_dir/node_modules/proper-lockfile/package.json"
printf 'export default { lockSync: () => () => {} };\n' >"$patched_dir/node_modules/proper-lockfile/index.js"
printf '{"type":"module","main":"index.js","exports":"./index.js"}\n' >"$patched_dir/node_modules/undici/package.json"
printf '' >"$patched_dir/node_modules/undici/index.js"
printf '{"type":"module","main":"index.js","exports":"./index.js"}\n' >"$patched_dir/node_modules/cross-spawn/package.json"
printf 'export default Object.assign(() => { throw new Error("cross-spawn stub invoked"); }, { sync: () => { throw new Error("cross-spawn stub invoked"); } });\n' >"$patched_dir/node_modules/cross-spawn/index.js"

node --input-type=module - "$patched_dir" <<'JS'
import { mkdir, mkdtemp, writeFile } from "node:fs/promises";
import { join } from "node:path";
import { pathToFileURL } from "node:url";
import assert from "node:assert/strict";

const root = process.argv[2];
const settings = await import(pathToFileURL(join(root, "dist/core/settings-manager.js")));
const cwd = await mkdtemp(join(root, "settings-test-"));
const agentDir = await mkdtemp(join(root, "agent-test-"));
await mkdir(join(cwd, ".pi"));
await writeFile(
  join(cwd, ".pi", "settings.json"),
  JSON.stringify({ selectorOverlayWidth: 88, selectorOverlayWidths: { model: 101, tree: 20 } }),
);
const manager = settings.SettingsManager.create(cwd, agentDir);
assert.equal(manager.getSelectorOverlayWidth(), 88);
assert.equal(manager.getSelectorOverlayWidth("model"), 101);
assert.equal(manager.getSelectorOverlayWidth("tree"), 40);
assert.equal(manager.getCompactionReserveTokens(), 16384);
assert.equal(manager.getCompactionKeepRecentTokens(), 20000);
assert.deepEqual(settings.CACHE_WARMING_MODES, ["off", "streaming", "idle"]);
JS

# Exercise the dedicated early-hook runner with a fake extension and no provider calls.
cat >"$patched_dir/dist/runner-order-test.mjs" <<'JS'
import assert from "node:assert/strict";
import { ExtensionRunner } from "./core/extensions/runner.js";

const events = [];
const extension = {
  path: "<offline-test>",
  handlers: new Map([
    ["before_model_availability", [async (event) => events.push(event.type)]],
  ]),
};
const runner = new ExtensionRunner([extension], {}, "/tmp", {}, {});
await runner.emitBeforeModelAvailability({
  type: "before_model_availability",
  reason: "startup",
});
events.push("model_refresh");
assert.deepEqual(events, ["before_model_availability", "model_refresh"]);
JS
cat >"$patched_dir/dist/modes/interactive/theme/theme.js" <<'JS'
export const theme = {};
JS
cat >"$patched_dir/dist/core/system-prompt.js" <<'JS'
export function buildSystemPrompt() { return ""; }
export function normalizeBuildSystemPromptOptions(options) { return options; }
JS
node "$patched_dir/dist/runner-order-test.mjs"

printf 'Pi 0.87 auth-startup + selector patches: PASS\n'
