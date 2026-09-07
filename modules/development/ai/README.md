# Agent browser on NixOS

The development module wraps the pinned `llm-agents` agent-browser package to
launch `pkgs.local.lightpanda` using its absolute Nix store path. The upstream
Linux launcher sets `AGENT_BROWSER_EXECUTABLE_PATH` to Chromium, so the wrapper
passes both `--engine lightpanda` and `--executable-path` as CLI arguments instead
of relying on environment variables or a user configuration file.

The original agent-browser package remains unchanged and cacheable. Lightpanda
is started and stopped by agent-browser; no separate service, fixed CDP port, or
browser download is required. Darwin keeps the original package.

After rebuilding, close any existing session before starting it with Lightpanda:

```sh
agent-browser close
agent-browser open https://example.com
agent-browser snapshot
agent-browser close
```

For a named session, use the same `--session NAME` on each command. The wrapper
does not terminate existing sessions automatically.

These launcher defaults take precedence over environment variables and JSON
configuration. Explicit CLI arguments come last and can override them. To use
Chromium for a task, override **both** `--engine chrome` and `--executable-path`
with the absolute path to an installed Chromium executable, using a fresh or
closed session. Overriding only the engine would still select Lightpanda's binary.

Lightpanda is for DOM/JavaScript automation, not graphical rendering. Use Chromium
for screenshots, headed browsing, extensions, or persistent browser profiles.

Upstream reference: [Lightpanda engine](https://agent-browser.dev/engines/lightpanda).
