-- Native RPC peer for broker tests. The real editor adapter is tested in dotfiles.
local launch_id = "0123456789abcdef0123456789abcdef"
local cwd = assert(vim.uv.fs_realpath(vim.env.PI_ASK_TEST_CWD))
local function emit(value)
  io.stdout:write(vim.json.encode(value) .. "\n")
  io.stdout:flush()
end

local bind_count, ack_count, close_count = 0, 0, 0
local bindings = {}
local done = false
_G.__piAsk = {
  bind = function(channel, launch, worktree, session_id)
    assert(launch == launch_id and worktree == cwd)
    assert(vim.api.nvim_get_chan_info(channel).mode == "rpc")
    bind_count = bind_count + 1
    local binding = {
      version = 1, channelId = channel, cwd = cwd, editorPid = vim.fn.getpid(),
      launchId = launch_id, ownerId = "test-owner", sessionId = session_id,
    }
    bindings[channel] = binding
    emit({ event = "bind", request = binding })
    vim.schedule(function()
      vim.rpcnotify(channel, "pi:nvim-prompt/v1", {
        version = 1, requestId = "test:" .. session_id, launchId = launch_id,
        sessionId = session_id, ownerId = "test-owner", sequence = bind_count,
        operation = "submit", cwd = cwd, editorPid = binding.editorPid,
        text = "explain æøå", context = vim.NIL,
      })
    end)
    return binding
  end,
  acknowledge = function(channel, launch, payload)
    assert(launch == launch_id and bindings[channel] ~= nil)
    ack_count = ack_count + 1
    emit({ event = "ack", payload = payload, channelId = channel })
    return true
  end,
  close = function(channel, launch)
    assert(launch == launch_id)
    if bindings[channel] == nil then return false end
    bindings[channel] = nil
    close_count = close_count + 1
    emit({ event = "closed", channelId = channel })
    if close_count == 2 then
      done = true
      emit({ event = "done", bindCount = bind_count, ackCount = ack_count, closeCount = close_count })
    end
    return true
  end,
}

local native = vim.v.servername
local alternate
if vim.env.PI_ASK_TEST_NATIVE then
  native = vim.fn.serverstart(vim.env.PI_ASK_TEST_NATIVE)
  alternate = vim.fn.serverstart(vim.env.PI_ASK_TEST_NATIVE .. ".alt")
elseif native == "" then
  native = vim.fn.serverstart()
end
emit({ event = "ready", socketPath = native, native = native, alternate = alternate })
assert(vim.wait(25000, function() return done end, 10), "Neovim broker fixture timed out")
vim.cmd("qa!")
