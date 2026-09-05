let implementation;
// Pi caches the first WebSocket constructor. Keep its identity stable while
// selecting a fresh per-test fake, so tests exercise the real transport path.
class TestWebSocket {
  constructor(...args) {
    return new implementation(...args);
  }
}
export async function withWebSocket(ctor, run) {
  const previous = globalThis.WebSocket;
  implementation = ctor;
  globalThis.WebSocket = TestWebSocket;
  try {
    return await run();
  } finally {
    globalThis.WebSocket = previous;
    implementation = undefined;
  }
}
