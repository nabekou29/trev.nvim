local state = require("trev.state")

local M = {}

--- Connect to trev daemon via Unix Domain Socket.
--- @param socket_path string
--- @param on_message fun(msg: table) callback for decoded JSON-RPC messages
--- @param on_disconnect fun() callback when connection is lost
function M.connect(socket_path, on_message, on_disconnect)
  local s = state.get()
  local pipe = vim.uv.new_pipe(false)
  if not pipe then
    vim.notify("[trev] Failed to create pipe", vim.log.levels.ERROR)
    return
  end

  pipe:connect(socket_path, function(err)
    if err then
      vim.schedule(function()
        vim.notify("[trev] Failed to connect: " .. err, vim.log.levels.ERROR)
        pipe:close()
      end)
      return
    end

    vim.schedule(function()
      s.pipe = pipe
      s.socket_path = socket_path
    end)

    pipe:read_start(function(read_err, data)
      if read_err then
        vim.schedule(function()
          vim.notify("[trev] Read error: " .. read_err, vim.log.levels.ERROR)
          M.disconnect()
          on_disconnect()
        end)
        return
      end

      if not data then
        -- EOF: trev process exited
        vim.schedule(function()
          M.disconnect()
          on_disconnect()
        end)
        return
      end

      vim.schedule(function()
        s.read_buf = s.read_buf .. data
        while true do
          local nl = s.read_buf:find("\n")
          if not nl then
            break
          end
          local line = s.read_buf:sub(1, nl - 1)
          s.read_buf = s.read_buf:sub(nl + 1)
          if #line > 0 then
            local ok, msg = pcall(vim.json.decode, line)
            if ok and msg then
              on_message(msg)
            end
          end
        end
      end)
    end)
  end)
end

--- Disconnect from trev daemon.
function M.disconnect()
  local s = state.get()
  if s.pipe then
    if not s.pipe:is_closing() then
      s.pipe:close()
    end
    s.pipe = nil
  end
  s.socket_path = nil
  s.read_buf = ""
  -- Cancel all pending callbacks
  for id, cb in pairs(s.pending) do
    cb(nil, { code = -1, message = "Disconnected" })
    s.pending[id] = nil
  end
end

--- @return boolean
function M.is_connected()
  local s = state.get()
  return s.pipe ~= nil and not s.pipe:is_closing()
end

--- Send a JSON-RPC 2.0 request (expects a response).
--- @param method string
--- @param params? table
--- @param callback? fun(result: any, error: any)
function M.send_request(method, params, callback)
  local s = state.get()
  if not M.is_connected() then
    if callback then
      callback(nil, { code = -1, message = "Not connected" })
    end
    return
  end

  local id = s.request_id
  s.request_id = s.request_id + 1

  local msg = {
    jsonrpc = "2.0",
    method = method,
    id = id,
  }
  if params then
    msg.params = params
  end

  if callback then
    s.pending[id] = callback
  end

  local data = vim.json.encode(msg) .. "\n"
  s.pipe:write(data)
end

--- Send a JSON-RPC 2.0 notification (no response expected).
--- @param method string
--- @param params? table
function M.send_notification(method, params)
  local s = state.get()
  if not M.is_connected() then
    return
  end

  local msg = {
    jsonrpc = "2.0",
    method = method,
  }
  if params then
    msg.params = params
  end

  local data = vim.json.encode(msg) .. "\n"
  s.pipe:write(data)
end

return M
