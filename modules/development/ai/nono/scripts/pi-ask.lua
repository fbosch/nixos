local uv = vim.uv
local VERSION, LIMIT = 1, 66 * 1024
local PROMPT = "pi:nvim-prompt/v1"

local function frozen(values)
  return setmetatable({}, {
    __index = values,
    __newindex = function() error("Pi Ask adapter is immutable", 2) end,
    __pairs = function() return pairs(values) end,
    __metatable = false,
  })
end

local function exact(value, required, optional)
  if type(value) ~= "table" then return false end
  local allowed = {}
  for _, key in ipairs(required) do
    allowed[key] = true
    if rawget(value, key) == nil then return false end
  end
  for _, key in ipairs(optional or {}) do allowed[key] = true end
  for key in pairs(value) do
    if type(key) ~= "string" or not allowed[key] then return false end
  end
  return true
end

local function encode(value)
  local ok, result = pcall(vim.json.encode, value)
  if not ok or type(result) ~= "string" or #result > LIMIT then return nil end
  return result .. "\n"
end

local function private_dir(path)
  local stat = uv.fs_lstat(path)
  if stat == nil then
    uv.fs_mkdir(path, 448)
    stat = uv.fs_lstat(path)
  end
  if stat == nil or stat.type == "link" or stat.type ~= "directory" then
    error("Pi Ask parent must be a real directory")
  end
  if stat.uid ~= uv.getuid() or stat.mode % 512 ~= 448 then
    error("Pi Ask parent must be owned by this user and mode 0700")
  end
end

local function random_name()
  local ok, bytes = pcall(uv.random, 16)
  if not ok or type(bytes) ~= "string" or #bytes ~= 16 then error("Pi Ask randomness unavailable") end
  local out = {}
  for i = 1, #bytes do out[i] = string.format("%02x", bytes:byte(i)) end
  return table.concat(out)
end

local function start(options)
  if type(options) ~= "table"
    or type(options.bind) ~= "function"
    or type(options.acknowledge) ~= "function"
    or type(options.closed) ~= "function"
    or type(options.launchId) ~= "string"
    or #options.launchId ~= 32
    or options.launchId:match("^[a-f0-9]+$") == nil
    or type(options.cwd) ~= "string"
    or options.cwd == ""
    or #options.cwd > 4096
    or options.cwd:find("\0", 1, true) ~= nil
    or uv.fs_realpath(options.cwd) ~= options.cwd
  then error("invalid Pi Ask host configuration") end

  local home = type(vim.env.HOME) == "string" and uv.fs_realpath(vim.env.HOME) or nil
  if home == nil then error("Pi Ask requires a real HOME directory") end
  local home_stat = uv.fs_lstat(home)
  if home_stat == nil or home_stat.type ~= "directory" then error("Pi Ask HOME is unavailable") end
  local base = home .. "/.pi-ipc"
  private_dir(base)

  local directory
  for _ = 1, 8 do
    local candidate = base .. "/" .. random_name()
    if uv.fs_mkdir(candidate, 448) then directory = candidate; break end
  end
  if directory == nil then error("could not create Pi Ask endpoint directory") end
  private_dir(directory)
  local path = directory .. "/ask.sock"
  if #path > 103 then uv.fs_rmdir(directory); error("Pi Ask socket path exceeds Unix limit") end

  local server = uv.new_pipe(false)
  local bound, bind_error = server:bind(path)
  if not bound then server:close(); uv.fs_rmdir(directory); error("could not bind Pi Ask socket: " .. tostring(bind_error)) end
  local stat = uv.fs_lstat(path)
  if stat == nil or stat.type ~= "socket" or not uv.fs_chmod(path, 384) then
    server:close(); uv.fs_unlink(path); uv.fs_rmdir(directory); error("could not secure Pi Ask socket")
  end
  local inode = stat.ino
  local peer, stopped, sequence = nil, false, 0

  local function cleanup_path()
    local current = uv.fs_lstat(path)
    if current and current.type == "socket" and (inode == nil or current.ino == inode) then uv.fs_unlink(path) end
    local dir = uv.fs_lstat(directory)
    if dir and dir.type == "directory" then uv.fs_rmdir(directory) end
  end

  local function close_peer(target, notify)
    if target == nil or target.closed then return end
    target.closed = true
    if target.timer then target.timer:stop(); target.timer:close(); target.timer = nil end
    if peer == target then peer = nil end
    if notify and target.bound then
      target.bound = false
      local channel_id = target.channelId
      vim.schedule(function() pcall(options.closed, channel_id) end)
    end
    if target.pipe and not target.pipe:is_closing() then target.pipe:close() end
  end

  local function send(target, message)
    if target.closed or target.pipe:is_closing() then return false end
    local frame = encode(message)
    if frame == nil then return false end
    return pcall(target.pipe.write, target.pipe, frame, function(err)
      if err and not target.closed then close_peer(target, true) end
    end)
  end

  local function reject(target, code)
    send(target, { version = VERSION, type = "error", code = code })
    close_peer(target, true)
  end

  local methods = {}
  function methods.is_open(channel_id)
    return not stopped and peer ~= nil and not peer.closed and peer.channelId == channel_id
  end

  local function handle_message(target, value)
    if type(value) ~= "table" or value.version ~= VERSION or type(value.type) ~= "string" then
      reject(target, "protocol-error"); return
    end
    if not target.bound then
      if not exact(value, { "version", "type", "launchId", "cwd", "sessionId" })
        or value.type ~= "bind"
        or value.launchId ~= options.launchId
        or type(value.cwd) ~= "string"
        or value.cwd ~= options.cwd
        or value.cwd:find("\0", 1, true)
        or type(value.sessionId) ~= "string" or #value.sessionId > 1024
        or value.sessionId:match("^[A-Za-z0-9][A-Za-z0-9._-]*$") == nil
        or value.sessionId:match("[A-Za-z0-9]$") == nil
      then reject(target, "protocol-error"); return end

      sequence = sequence + 1
      local request = { launchId = value.launchId, cwd = value.cwd, sessionId = value.sessionId }
      local channel_id, editor_pid = sequence, vim.fn.getpid()
      target.channelId = channel_id
      local ok, binding = pcall(options.bind, {
        channelId = channel_id, editorPid = editor_pid, launchId = request.launchId,
        cwd = request.cwd, sessionId = request.sessionId, replacePending = true,
      })
      if not ok or not exact(binding, {
        "version", "channelId", "cwd", "editorPid", "launchId", "ownerId", "sessionId",
      }) or binding.version ~= VERSION or binding.channelId ~= channel_id
        or binding.editorPid ~= editor_pid or binding.launchId ~= request.launchId
        or binding.sessionId ~= request.sessionId or type(binding.cwd) ~= "string"
        or type(binding.ownerId) ~= "string" or #binding.ownerId == 0 or #binding.ownerId > 128
      then reject(target, "bind-rejected"); return end
      target.bound = true
      if target.timer then target.timer:stop(); target.timer:close(); target.timer = nil end
      if not send(target, { version = VERSION, type = "bound", binding = binding }) then close_peer(target, true) end
      return
    end

    if value.type == "close" and exact(value, { "version", "type" }) then
      close_peer(target, true); return
    end
    if value.type ~= "ack" or not exact(value, { "version", "type", "payload" })
      or not exact(value.payload, {
        "version", "requestId", "launchId", "sessionId", "ownerId", "outcome", "state",
      }, { "code" })
    then reject(target, "protocol-error"); return end
    pcall(options.acknowledge, value.payload, target.channelId)
  end

  local function receive(target, chunk)
    target.buffer = target.buffer .. chunk
    if #target.buffer > LIMIT and not target.buffer:find("\n", 1, true) then reject(target, "protocol-error"); return end
    while true do
      local newline = target.buffer:find("\n", 1, true)
      if not newline then return end
      if newline == 1 or newline - 1 > LIMIT then reject(target, "protocol-error"); return end
      local line = target.buffer:sub(1, newline - 1)
      target.buffer = target.buffer:sub(newline + 1)
      local ok, value = pcall(vim.json.decode, line)
      if not ok then reject(target, "protocol-error"); return end
      handle_message(target, value)
      if target.closed then return end
    end
  end

  local listen_ok, listen_error = server:listen(16, function(err)
    if stopped or err then return end
    local pipe = uv.new_pipe(false)
    if not server:accept(pipe) then pipe:close(); return end
    if peer then
      local rejected = { pipe = pipe, buffer = "", closed = false }
      reject(rejected, "bind-rejected"); return
    end
    local target = { pipe = pipe, buffer = "", closed = false, bound = false }
    peer = target
    target.timer = uv.new_timer()
    target.timer:start(5000, 0, function() if not target.bound then reject(target, "bind-rejected") end end)
    pipe:read_start(function(read_error, chunk)
      if read_error or chunk == nil then close_peer(target, true); return end
      vim.schedule(function()
        if not target.closed then receive(target, chunk) end
      end)
    end)
  end)
  if not listen_ok then server:close(); cleanup_path(); error("could not listen on Pi Ask socket: " .. tostring(listen_error)) end

  function methods.notify(channel_id, method_name, request)
    if method_name ~= PROMPT or not methods.is_open(channel_id) then return false end
    return send(peer, { version = VERSION, type = "prompt", request = request })
  end
  function methods.close(channel_id)
    if not methods.is_open(channel_id) then return false end
    close_peer(peer, true); return true
  end
  function methods.stop()
    if stopped then return end
    stopped = true
    close_peer(peer, true)
    if not server:is_closing() then server:close() end
    cleanup_path()
  end
  methods.socketPath = path
  return frozen(methods)
end

return frozen({ start = start })
