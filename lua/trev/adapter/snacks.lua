--- Snacks.nvim terminal adapter for trev.nvim.
--- Uses Snacks.terminal for terminal management.

local snacks_ok, Snacks = pcall(require, "snacks")

--- @class trev.SnacksAdapter: trev.Adapter
local SnacksAdapter = {}
SnacksAdapter.__index = SnacksAdapter

--- @return trev.SnacksAdapter
function SnacksAdapter.new()
  if not snacks_ok then
    error("[trev] snacks.nvim is required for the snacks adapter")
  end
  return setmetatable({}, SnacksAdapter)
end

--- @type table|nil
local term = nil

--- Build win config for Snacks.terminal.
--- @param mode trev.Position
--- @param opts trev.AdapterOpts
--- @return table
local function make_win_config(mode, opts)
  if mode == "float" then
    local float = opts.float or {}
    local win = {
      position = "float",
      border = "rounded",
    }
    if float.width then
      win.width = float.width
    end
    if float.height then
      win.height = float.height
    end
    return win
  else
    return {
      position = opts.side or "left",
      width = opts.width or 30,
      wo = { winbar = "" },
    }
  end
end

--- Create and open a new Snacks terminal.
--- @param cmd string[] command to run
--- @param mode trev.Position
--- @param opts trev.AdapterOpts
--- @return trev.AdapterHandle|nil
local function create_and_open(cmd, mode, opts)
  local win_config = make_win_config(mode, opts)

  local cmd_str = table.concat(cmd, " ")

  term = Snacks.terminal.open(cmd_str, {
    win = win_config,
    auto_close = false,
    interactive = true,
  })

  if not term then
    vim.notify("[trev] Failed to start trev via snacks", vim.log.levels.ERROR)
    return nil
  end

  -- Watch for process exit via TermClose
  if term.buf then
    vim.api.nvim_create_autocmd("TermClose", {
      buffer = term.buf,
      once = true,
      callback = function()
        local exit_code = vim.v.event and vim.v.event.status or 0
        vim.schedule(function()
          opts.on_exit(exit_code)
        end)
      end,
    })
  end

  local pid = nil
  if term.buf and vim.api.nvim_buf_is_valid(term.buf) then
    local job_id = vim.b[term.buf].terminal_job_id
    if job_id then
      local ok, p = pcall(vim.fn.jobpid, job_id)
      if ok then
        pid = p
      end
    end
  end

  --- @type trev.AdapterHandle
  local handle = {
    buf = term.buf,
    win = term.win,
    pid = pid,
    job_id = term.buf and vim.b[term.buf].terminal_job_id or nil,
  }

  vim.schedule(function()
    opts.on_ready(handle)
  end)

  return handle
end

--- Open trev in a side panel.
--- @param cmd string[] command to run
--- @param opts trev.AdapterOpts
--- @return trev.AdapterHandle|nil
function SnacksAdapter:open_panel(cmd, opts)
  return create_and_open(cmd, "panel", opts)
end

--- Open trev in a floating window.
--- @param cmd string[] command to run
--- @param opts trev.AdapterOpts
--- @return trev.AdapterHandle|nil
function SnacksAdapter:open_float(cmd, opts)
  return create_and_open(cmd, "float", opts)
end

--- Close the window without killing the process.
--- @param handle trev.AdapterHandle
function SnacksAdapter:close(handle)
  if term and term:win_valid() then
    term:hide()
  end
  handle.win = nil
end

--- Show an existing terminal in a new window.
--- @param handle trev.AdapterHandle
--- @param mode trev.Position
--- @param opts trev.AdapterOpts
function SnacksAdapter:show(handle, mode, opts)
  if not term or not term:buf_valid() then
    return
  end

  term:show()
  handle.win = term.win
  handle.buf = term.buf
end

--- Check if the terminal window is visible.
--- @param handle trev.AdapterHandle
--- @return boolean
function SnacksAdapter:is_visible(handle)
  return term ~= nil and term:win_valid()
end

--- Check if the terminal process is still alive.
--- @param handle trev.AdapterHandle
--- @return boolean
function SnacksAdapter:is_alive(handle)
  if not term then
    return false
  end
  return term:buf_valid()
end

--- Focus the trev window and enter terminal mode.
--- @param handle trev.AdapterHandle
function SnacksAdapter:focus(handle)
  if term and term:win_valid() then
    term:focus()
  end
end

return SnacksAdapter
