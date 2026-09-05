# Pi native OpenAI capabilities

`pi-openai-capabilities.patch` targets Pi **0.85.0** from the pinned `llm-agents`
input. `default.nix` applies it after dependencies are installed and before Bun
compiles Pi. The existing selector-overlay and fullscreen-image patches remain
in place.

The dotfiles extension `~/dotfiles/.pi/agent/extensions/openai-capabilities.ts`
opts in both `openai-codex/gpt-6-astra` and `openai-codex/gpt-6-astra-fast` through
`registerOpenAICapabilities({ provider, model, asyncTools, steering, asyncToolNames? })`.
Registration uses exact provider/model selectors, rejects duplicates, and cannot
change during a run. Other models retain the ordinary agent loop. Fast aliases
still request their base model with `service_tier: "priority"`; standard Astra
keeps its existing service tier.

## Behavior and limits

- Advertised client tools receive `async: true`. Complete calls can start while
  the response streams, through Pi's existing validation, permission, execution,
  update, and result hooks. Partial JSON cannot trigger execution.
- Results are collected at response boundaries and submitted once with their
  original OpenAI call IDs. This implementation does not start an explicit next
  response while tools from the preceding response are still running.
- Steering uses `response.steer` on the same WebSocket. Acknowledgments must match
  the reserved predecessor and server-assigned `steer.id`. Acceptance alone does
  not mark input delivered; the successor response confirms incorporation. Pending
  steering can request predecessor tool outputs without repeating the input.
- Received messages are decoded before subsequent socket close/error events.
  Explicit abort remains immediate and discards unfinished decoding.
- Rejected or uncertain steering retains its original input but is excluded from
  automatic submission, including subsequent runs. Follow-up messages remain
  separate. Review the response before explicitly resending uncertain input.
- Checkpoints retain call intent, results, and input delivery state. Recovery
  reports unknown tool outcomes rather than executing those calls again. Failed
  and cross-model native history preserves chronological, attributed tool
  outcomes instead of manufacturing adjacent results.
- Native mode rejects SSE and does not retry or silently downgrade an uncertain
  exchange. Abort waits for admitted cooperative tool work to settle. Compaction,
  model changes, and reload are blocked while a native exchange is active.

## Verification

The package build runs `tests/` with `PI_NATIVE_TEST_ROOT` pointing at the patched
npm tree. The tests use synthetic credentials and fake WebSockets, including
cross-package transport, execution, and persisted-replay cases. They make no live
model requests. The x86_64-linux package and its compiled CLI have been checked;
other platforms have not. A full upstream declaration check is blocked by
`@google/genai` importing the absent optional `@modelcontextprotocol/sdk` package;
no dependency was added to work around it.

Building does not activate the package or restow the renamed extension. Deploy
both repositories through their normal workflows before restarting Pi.

Live async tool execution and one steering continuation have been observed on
standard Astra. Text-only steering attempts also disconnected after acceptance.
The receive-order and acknowledgment-correlation fixes have not yet been verified
against the live backend; the cause of those disconnects remains unconfirmed.
The patch does not establish server-side capability or authentication entitlement.

Before upgrading Pi, review the patch against the new npm source and rerun the
build-time tests. The version assertion deliberately stops an unchecked upgrade.
Retire the patch when upstream provides equivalent lifecycle and recovery support.
