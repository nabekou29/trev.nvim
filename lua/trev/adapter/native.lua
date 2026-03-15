--- Native terminal adapter for trev.nvim.
--- Uses Neovim's built-in terminal (termopen) with vsplit for panel and floating window for float.
--- Supports hiding the window while keeping the terminal process alive.

--- @class trev.NativeAdapter: trev.Adapter
local NativeAdapter = {}
NativeAdapter.__index = NativeAdapter

--- @return trev.NativeAdapter
function NativeAdapter.new()
  return setmetatable({}, NativeAdapter)
end

--- Configure window options for trev panel.
--- @param win number window ID
local function setup_panel_win(win)
  vim.wo[win].number = false
  vim.wo[win].relativenumber = false
  vim.wo[win].signcolumn = "no"
  vim.wo[win].winfixwidth = true
  vim.wo[win].winfixheight = true
  vim.wo[win].foldcolumn = "0"
  vim.wo[win].spell = false
  vim.wo[win].list = false
end

--- Configure buffer options for trev terminal.
--- @param buf number buffer ID
local function setup_term_buf(buf)
  vim.bo[buf].filetype = "trev"
  vim.bo[buf].bufhidden = "hide"
  vim.bo[buf].buflisted = false

  -- Auto-enter terminal mode when focusing this buffer
  vim.api.nvim_create_autocmd("BufEnter", {
    buffer = buf,
    callback = function()
      if vim.api.nvim_get_mode().mode ~= "t" then
        vim.cmd("startinsert")
      end
    end,
  })
end

--- Create a floating window configuration.
--- @param float_config trev.FloatConfig
--- @return table nvim_open_win config
local function make_float_config(float_config)
  local editor_width = vim.o.columns
  local editor_height = vim.o.lines - vim.o.cmdheight

  local width = float_config.width
  local height = float_config.height

  -- Convert fractions to absolute values
  if width > 0 and width <= 1 then
    width = math.floor(editor_width * width)
  end
  if height > 0 and height <= 1 then
    height = math.floor(editor_height * height)
  end

  width = math.max(1, math.floor(width))
  height = math.max(1, math.floor(height))

  local col = math.floor((editor_width - width) / 2)
  local row = math.floor((editor_height - height) / 2)

  return {
    relative = "editor",
    width = width,
    height = height,
    col = col,
    row = row,
    style = "minimal",
    border = "rounded",
  }
end

--- Open trev in a side panel (vsplit).
--- @param cmd string[] command to run
--- @param opts trev.AdapterOpts
--- @return trev.AdapterHandle|nil
function NativeAdapter:open_panel(cmd, opts)
  -- Create vsplit on the left
  vim.cmd("topleft " .. (opts.width or 30) .. "vsplit")
  local win = vim.api.nvim_get_current_win()
  local buf = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_win_set_buf(win, buf)

  setup_panel_win(win)
  setup_term_buf(buf)

  local job_id = vim.fn.termopen(cmd, {
    on_exit = function(_, exit_code)
      vim.schedule(function()
        opts.on_exit(exit_code)
      end)
    end,
  })

  if job_id <= 0 then
    vim.notify("[trev] Failed to start trev process", vim.log.levels.ERROR)
    vim.api.nvim_win_close(win, true)
    return nil
  end

  local pid = vim.fn.jobpid(job_id)

  --- @type trev.AdapterHandle
  local handle = {
    buf = buf,
    win = win,
    pid = pid,
    job_id = job_id,
  }

  vim.cmd("startinsert")

  vim.schedule(function()
    opts.on_ready(handle)
  end)

  return handle
end

--- Open trev in a floating window.
--- @param cmd string[] command to run
--- @param opts trev.AdapterOpts
--- @return trev.AdapterHandle|nil
function NativeAdapter:open_float(cmd, opts)
  local buf = vim.api.nvim_create_buf(false, true)
  local win_config = make_float_config(opts.float or { width = 0.6, height = 0.7 })
  local win = vim.api.nvim_open_win(buf, true, win_config)

  setup_term_buf(buf)

  local job_id = vim.fn.termopen(cmd, {
    on_exit = function(_, exit_code)
      vim.schedule(function()
        opts.on_exit(exit_code)
      end)
    end,
  })

  if job_id <= 0 then
    vim.notify("[trev] Failed to start trev process", vim.log.levels.ERROR)
    vim.api.nvim_win_close(win, true)
    return nil
  end

  local pid = vim.fn.jobpid(job_id)

  --- @type trev.AdapterHandle
  local handle = {
    buf = buf,
    win = win,
    pid = pid,
    job_id = job_id,
  }

  vim.cmd("startinsert")

  vim.schedule(function()
    opts.on_ready(handle)
  end)

  return handle
end

--- Close the window without killing the process.
--- @param handle trev.AdapterHandle
function NativeAdapter:close(handle)
  if handle.win and vim.api.nvim_win_is_valid(handle.win) then
    vim.api.nvim_win_close(handle.win, false)
  end
  handle.win = nil
end

--- Show an existing terminal buffer in a new window.
--- @param handle trev.AdapterHandle
--- @param mode trev.Position
--- @param opts trev.AdapterOpts
function NativeAdapter:show(handle, mode, opts)
  if not handle.buf or not vim.api.nvim_buf_is_valid(handle.buf) then
    return
  end

  if mode == "float" then
    local win_config = make_float_config(opts.float or { width = 0.6, height = 0.7 })
    local win = vim.api.nvim_open_win(handle.buf, true, win_config)
    handle.win = win
  else
    -- Panel mode: vsplit on the left
    vim.cmd("topleft " .. (opts.width or 30) .. "vsplit")
    local win = vim.api.nvim_get_current_win()
    vim.api.nvim_win_set_buf(win, handle.buf)
    setup_panel_win(win)
    handle.win = win
  end

  vim.cmd("startinsert")
end

--- Check if the terminal window is visible.
--- @param handle trev.AdapterHandle
--- @return boolean
function NativeAdapter:is_visible(handle)
  return handle.win ~= nil and vim.api.nvim_win_is_valid(handle.win)
end

--- Check if the terminal process is still alive.
--- @param handle trev.AdapterHandle
--- @return boolean
function NativeAdapter:is_alive(handle)
  if not handle.buf or not vim.api.nvim_buf_is_valid(handle.buf) then
    return false
  end
  if not handle.job_id then
    return false
  end
  -- Check if job is still running
  local ok, _ = pcall(vim.fn.jobpid, handle.job_id)
  return ok
end

--- Focus the trev window and enter terminal mode.
--- @param handle trev.AdapterHandle
function NativeAdapter:focus(handle)
  if handle.win and vim.api.nvim_win_is_valid(handle.win) then
    vim.api.nvim_set_current_win(handle.win)
    -- Enter insert mode to interact with terminal
    vim.cmd("startinsert")
  end
end

return NativeAdapter
