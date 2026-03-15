local config = require("trev.config")
local state = require("trev.state")

local M = {}

--- Handle a decoded JSON-RPC message from trev.
--- @param msg table decoded JSON object
function M.handle_message(msg)
  -- Response message (has id)
  if msg.id then
    M._handle_response(msg)
    return
  end

  -- Notification message
  if msg.method then
    M._handle_notification(msg)
    return
  end
end

--- Handle a JSON-RPC response.
--- @param msg table
function M._handle_response(msg)
  local s = state.get()
  local cb = s.pending[msg.id]
  if cb then
    s.pending[msg.id] = nil
    cb(msg.result, msg.error)
  end
end

--- Handle a JSON-RPC notification from trev.
--- @param msg table
function M._handle_notification(msg)
  local method = msg.method
  local params = msg.params or {}

  if method == "open_file" then
    M._handle_open_file(params)
    return
  end

  -- Custom handler (user-defined or keybinding auto-registered)
  local cfg = config.get()
  local handler = cfg.handlers[method]
  if handler then
    handler(params)
  end
end

--- Handle open_file notification.
--- @param params table { path: string }
function M._handle_open_file(params)
  local s = state.get()
  local path = params.path
  if not path then
    return
  end

  local escaped = vim.fn.fnameescape(path)

  if s.mode == "float" then
    -- Float mode: close float, restore prev_win, then edit
    local trev = require("trev")
    trev.close()
    if s.prev_win and vim.api.nvim_win_is_valid(s.prev_win) then
      vim.api.nvim_set_current_win(s.prev_win)
    end
    vim.cmd("edit " .. escaped)
  else
    -- Panel mode: find editor window, focus it, then edit
    local editor_win = M._find_editor_window()
    if editor_win then
      vim.api.nvim_set_current_win(editor_win)
    end
    vim.cmd("edit " .. escaped)
  end
end

--- Find a non-trev, non-float window suitable for editing files.
--- @return number|nil window ID
function M._find_editor_window()
  local s = state.get()
  local current_win = vim.api.nvim_get_current_win()
  local wins = vim.api.nvim_tabpage_list_wins(0)

  for _, win in ipairs(wins) do
    if win ~= current_win then
      local win_config = vim.api.nvim_win_get_config(win)
      -- Skip floating windows
      if win_config.relative == "" then
        local buf = vim.api.nvim_win_get_buf(win)
        local buftype = vim.bo[buf].buftype
        -- Skip terminal and special buffers
        if buftype ~= "terminal" and buftype ~= "nofile" and buftype ~= "prompt" then
          return win
        end
      end
    end
  end

  -- Fallback: if trev panel has a handle, try prev_win
  if s.prev_win and vim.api.nvim_win_is_valid(s.prev_win) then
    return s.prev_win
  end

  return nil
end

return M
