--- Toggleterm adapter for trev.nvim.
--- Uses toggleterm.nvim's Terminal class for better terminal compatibility.

local ok, Terminal = pcall(require, "toggleterm.terminal")
if ok then
  Terminal = Terminal.Terminal
end

--- @class trev.ToggletTermAdapter: trev.Adapter
local ToggletermAdapter = {}
ToggletermAdapter.__index = ToggletermAdapter

--- @return trev.ToggletTermAdapter
function ToggletermAdapter.new()
  if not ok then
    error("[trev] toggleterm.nvim is required for the toggleterm adapter")
  end
  return setmetatable({}, ToggletermAdapter)
end

--- @type table|nil
local term = nil

--- Resolve a single dimension value for toggleterm float_opts.
--- @param value number
--- @param total_fn fun(): number
--- @return number|fun(): number
local function resolve_size(value, total_fn)
  if value > 0 and value <= 1 then
    return function()
      return math.floor(total_fn() * value)
    end
  end
  return math.floor(value)
end

--- Build float_opts from trev.FloatConfig. Returns nil when no size is specified.
--- @param float_config trev.FloatConfig
--- @return table|nil
local function make_float_opts(float_config)
  local opts = { border = "rounded" }
  if float_config.width then
    opts.width = resolve_size(float_config.width, function() return vim.o.columns end)
  end
  if float_config.height then
    opts.height = resolve_size(float_config.height, function() return vim.o.lines - vim.o.cmdheight end)
  end
  return opts
end

--- Create and open a new toggleterm Terminal.
--- @param cmd string[] command to run
--- @param direction string "vertical" | "float"
--- @param opts trev.AdapterOpts
--- @return trev.AdapterHandle|nil
local function create_and_open(cmd, direction, opts)
  local cmd_str = table.concat(cmd, " ")

  local term_opts = {
    cmd = cmd_str,
    direction = direction,
    hidden = true,
    close_on_exit = false,
    on_exit = function(_, _, exit_code)
      vim.schedule(function()
        opts.on_exit(exit_code)
      end)
    end,
  }

  if direction == "vertical" then
    term_opts.size = opts.width or 30
  elseif direction == "float" then
    term_opts.float_opts = make_float_opts(opts.float or {})
  end

  term = Terminal:new(term_opts)
  term:open()

  -- Wait for terminal to be ready
  vim.schedule(function()
    --- @type trev.AdapterHandle
    local handle = {
      buf = term.bufnr,
      win = term.window,
      pid = term.job_id and vim.fn.jobpid(term.job_id) or nil,
      job_id = term.job_id,
    }
    opts.on_ready(handle)
  end)

  return {
    buf = term.bufnr,
    win = term.window,
    pid = nil,
    job_id = term.job_id,
  }
end

--- Open trev in a side panel (vsplit).
--- @param cmd string[] command to run
--- @param opts trev.AdapterOpts
--- @return trev.AdapterHandle|nil
function ToggletermAdapter:open_panel(cmd, opts)
  return create_and_open(cmd, "vertical", opts)
end

--- Open trev in a floating window.
--- @param cmd string[] command to run
--- @param opts trev.AdapterOpts
--- @return trev.AdapterHandle|nil
function ToggletermAdapter:open_float(cmd, opts)
  return create_and_open(cmd, "float", opts)
end

--- Close the window without killing the process.
--- @param handle trev.AdapterHandle
function ToggletermAdapter:close(handle)
  if term and term:is_open() then
    term:close()
  end
  handle.win = nil
end

--- Show an existing terminal in a new window.
--- @param handle trev.AdapterHandle
--- @param mode trev.Position
--- @param opts trev.AdapterOpts
function ToggletermAdapter:show(handle, mode, opts)
  if not term then
    return
  end

  if mode == "float" then
    term.direction = "float"
    term.float_opts = make_float_opts(opts.float or {})
  else
    term.direction = "vertical"
    term.size = opts.width or 30
  end

  term:open()
  handle.win = term.window
  handle.buf = term.bufnr
end

--- Check if the terminal window is visible.
--- @param handle trev.AdapterHandle
--- @return boolean
function ToggletermAdapter:is_visible(handle)
  return term ~= nil and term:is_open()
end

--- Check if the terminal process is still alive.
--- @param handle trev.AdapterHandle
--- @return boolean
function ToggletermAdapter:is_alive(handle)
  if not term or not term.job_id then
    return false
  end
  local alive, _ = pcall(vim.fn.jobpid, term.job_id)
  return alive
end

--- Focus the trev window and enter terminal mode.
--- @param handle trev.AdapterHandle
function ToggletermAdapter:focus(handle)
  if term and term:is_open() then
    term:focus()
  end
end

return ToggletermAdapter
