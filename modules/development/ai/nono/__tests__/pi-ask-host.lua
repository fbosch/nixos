local launch_id = "0123456789abcdef0123456789abcdef"
local cwd = assert(vim.uv.fs_realpath(vim.env.PI_ASK_TEST_CWD))
local host_path = assert(vim.env.PI_ASK_TEST_HOST)
local emit = function(value)
  io.stdout:write(vim.json.encode(value) .. "\n")
  io.stdout:flush()
end

local host
local bind_count, ack_count, close_count = 0, 0, 0
local done = false
host = dofile(host_path).start({
  launchId = launch_id,
  cwd = cwd,
  bind = function(request)
    bind_count = bind_count + 1
    emit({ event = "bind", request = request })
    local binding = {
      version = 1,
      channelId = request.channelId,
      cwd = request.cwd,
      editorPid = request.editorPid,
      launchId = request.launchId,
      ownerId = "test-owner",
      sessionId = request.sessionId,
    }
    vim.schedule(function()
      host.notify(request.channelId, "pi:nvim-prompt/v1", {
        version = 1,
        requestId = "test:" .. request.sessionId,
        launchId = request.launchId,
        sessionId = request.sessionId,
        ownerId = "test-owner",
        sequence = bind_count,
      })
    end)
    return binding
  end,
  acknowledge = function(payload, channel_id)
    ack_count = ack_count + 1
    emit({ event = "ack", payload = payload, channelId = channel_id })
  end,
  closed = function(channel_id)
    close_count = close_count + 1
    emit({ event = "closed", channelId = channel_id })
    if close_count == 2 then
      host.stop()
      done = true
      emit({ event = "done", bindCount = bind_count, ackCount = ack_count, closeCount = close_count })
    end
  end,
})

local native, alternate
if vim.env.PI_ASK_TEST_NATIVE then
  native = vim.fn.serverstart(vim.env.PI_ASK_TEST_NATIVE)
  alternate = vim.fn.serverstart(vim.env.PI_ASK_TEST_NATIVE .. ".alt")
end
emit({ event = "ready", socketPath = host.socketPath, native = native, alternate = alternate })
assert(vim.wait(25000, function() return done end, 10), "Pi Ask fixture timed out")
vim.cmd("qa!")
