local adapter_factory = require("trev.adapter")
local command = require("trev.command")
local config = require("trev.config")
local handlers = require("trev.handlers")
local ipc = require("trev.ipc")
local keybindings = require("trev.keybindings")
local socket = require("trev.socket")
local state = require("trev.state")

local M = {}

M.actions = require("trev.actions")

--- @type trev.Adapter|nil
local adapter = nil

--- @type trev.BindingEntry[]
local binding_entries = {}

--- @param opts? trev.UserConfig
function M.setup(opts)
  config.apply(opts)
  local cfg = config.get()

  -- Merge default keybindings with user keybindings
  local merged_keybindings = keybindings.merge(cfg.default_keybindings, cfg.keybindings)

  -- Normalize keybindings and register handlers
  binding_entries = keybindings.normalize(merged_keybindings)
  keybindings.register_handlers(binding_entries, cfg.handlers)

  -- Resolve adapter
  adapter = adapter_factory.resolve(cfg.adapter)

  -- Register :Trev command
  command.register()

  -- Cleanup on VimLeavePre
  vim.api.nvim_create_autocmd("VimLeavePre", {
    callback = function()
      M._cleanup()
    end,
  })
end

--- Build the command line for trev.
--- @param dir string workspace directory
--- @return string[]
--- @param dir string
--- @param reveal_path? string file path to reveal on startup
local function build_cmd(dir, reveal_path)
  local cfg = config.get()
  local s = state.get()
  local cmd = { cfg.trev_path, "--ipc", dir }

  -- Reveal file on startup
  if reveal_path and reveal_path ~= "" then
    table.insert(cmd, "--reveal")
    table.insert(cmd, reveal_path)
  end

  -- Config override for keybindings and preview
  local override_path = keybindings.write_override_file(binding_entries, cfg.neovim_preview)
  if override_path then
    s.override_path = override_path
    table.insert(cmd, "--config-override")
    table.insert(cmd, override_path)
  end

  return cmd
end

--- Start a new trev instance.
--- @param mode trev.Position
--- @param dir string
--- @param reveal_path? string file to reveal on startup
local function start_instance(mode, dir, reveal_path)
  local s = state.get()
  local cfg = config.get()

  local cmd = build_cmd(dir, reveal_path)

  --- @type trev.AdapterOpts
  local opts = {
    side = cfg.side,
    width = cfg.width,
    float = cfg.float,
    on_exit = function(exit_code)
      M._on_exit(exit_code)
    end,
    on_ready = function(handle)
      s.handle = handle
      s.mode = mode
      s.dir = dir

      -- Connect IPC via socket discovery
      if handle.pid then
        socket.find_for_pid(handle.pid, function(socket_path)
          if socket_path then
            M._connect_ipc(socket_path)
          else
            vim.notify("[trev] Could not find socket for PID " .. handle.pid, vim.log.levels.WARN)
          end
        end)
      end
    end,
  }

  if mode == "float" then
    s.prev_win = vim.api.nvim_get_current_win()
    adapter:open_float(cmd, opts)
    M._setup_float_auto_close()
  else
    adapter:open_panel(cmd, opts)
  end
end

--- Set up autocmd to close float when focus leaves.
function M._setup_float_auto_close()
  local s = state.get()
  local float_augroup = vim.api.nvim_create_augroup("TrevFloatAutoClose", { clear = true })
  vim.api.nvim_create_autocmd("WinLeave", {
    group = float_augroup,
    callback = function()
      -- Only close if still in float mode and window is valid
      if s.mode == "float" and s.handle and adapter:is_visible(s.handle) then
        vim.schedule(function()
          -- Check that focus actually moved away from the float
          if s.handle and s.handle.win and vim.api.nvim_get_current_win() ~= s.handle.win then
            M.close()
          end
        end)
      end
      -- Clean up this augroup once float is gone
      if s.mode ~= "float" then
        vim.api.nvim_del_augroup_by_id(float_augroup)
      end
    end,
  })
end

--- Connect to trev IPC and set up auto-reveal.
--- @param socket_path string
function M._connect_ipc(socket_path)
  ipc.connect(socket_path, handlers.handle_message, function()
    -- on disconnect
    M._on_ipc_disconnect()
  end, function()
    -- on connect
    M._on_ipc_connect()
  end)
end

--- Called when IPC connection is established.
function M._on_ipc_connect()
  -- Set up auto-reveal
  M._setup_auto_reveal()

  -- Initial reveal of current buffer
  local cfg = config.get()
  if cfg.auto_reveal then
    local path = vim.api.nvim_buf_get_name(0)
    if path and path ~= "" and not M._is_special_buffer(0) then
      ipc.send_notification("reveal", { path = path })
    end
  end

  -- Sync initial state (preview, etc.)
  ipc.send_request("get_state", nil, function(result)
    if result and result.preview then
      require("trev.preview").on_preview(result.preview)
    end
  end)
end

--- Set up BufEnter autocmd for auto-reveal.
function M._setup_auto_reveal()
  local s = state.get()
  local cfg = config.get()

  if not cfg.auto_reveal then
    return
  end

  -- Clean up existing augroup
  if s.augroup then
    vim.api.nvim_del_augroup_by_id(s.augroup)
  end

  s.augroup = vim.api.nvim_create_augroup("TrevAutoReveal", { clear = true })
  vim.api.nvim_create_autocmd("BufEnter", {
    group = s.augroup,
    callback = function(ev)
      if not ipc.is_connected() then
        return
      end
      if M._is_special_buffer(ev.buf) then
        return
      end
      local path = vim.api.nvim_buf_get_name(ev.buf)
      if path and path ~= "" then
        ipc.send_notification("reveal", { path = path })
      end
    end,
  })
end

--- Check if a buffer is a special buffer that should be skipped for auto-reveal.
--- @param buf number
--- @return boolean
function M._is_special_buffer(buf)
  local buftype = vim.bo[buf].buftype
  if
    buftype == "terminal"
    or buftype == "quickfix"
    or buftype == "help"
    or buftype == "nofile"
    or buftype == "prompt"
  then
    return true
  end
  local filetype = vim.bo[buf].filetype
  if filetype == "trev" then
    return true
  end
  return false
end

--- Handle trev process exit.
--- @param exit_code number
function M._on_exit(exit_code)
  local s = state.get()
  ipc.disconnect()

  if exit_code ~= 0 then
    -- Keep window open so the user can see the error
    vim.notify("[trev] Process exited with code " .. exit_code, vim.log.levels.ERROR)
    -- Prevent bufhidden="hide" from keeping a dead terminal around
    if s.handle and s.handle.buf and vim.api.nvim_buf_is_valid(s.handle.buf) then
      vim.bo[s.handle.buf].bufhidden = "wipe"
    end
    state.reset()
    return
  end

  -- Close preview overlay
  require("trev.preview").hide()

  -- Normal exit: close window and clean up
  if adapter and s.handle then
    adapter:close(s.handle)
  end

  -- Clean up temp file
  if s.override_path then
    os.remove(s.override_path)
  end

  -- Clean up auto-reveal
  if s.augroup then
    vim.api.nvim_del_augroup_by_id(s.augroup)
  end

  state.reset()
end

--- Handle IPC disconnect (socket closed without process exit).
function M._on_ipc_disconnect()
  -- IPC is already disconnected via ipc.disconnect()
  -- Auto-reveal will no-op since is_connected() returns false
end

--- Handle dir change: quit existing instance if dir differs.
--- @param dir string new directory
--- @param callback fun() called after existing instance is cleaned up or immediately if no change needed
local function handle_dir_change(dir, callback)
  local s = state.get()

  -- No existing instance
  if not s.handle or not adapter:is_alive(s.handle) then
    callback()
    return
  end

  -- Same dir, no change needed
  if s.dir and vim.fn.resolve(s.dir) == vim.fn.resolve(dir) then
    callback()
    return
  end

  -- Different dir: quit existing and restart
  if ipc.is_connected() then
    ipc.send_request("quit", nil, function()
      ipc.disconnect()
      -- Wait for process exit, then callback
      vim.defer_fn(callback, 100)
    end)
  else
    -- Force stop
    if s.handle.job_id then
      vim.fn.jobstop(s.handle.job_id)
    end
    state.reset()
    callback()
  end
end

--- Toggle trev visibility.
--- @param opts? { position?: trev.Position, dir?: string, reveal?: boolean }
function M.toggle(opts)
  opts = opts or {}
  local s = state.get()
  local target_mode = opts.position or "panel"
  local dir = opts.dir or s.dir or vim.fn.getcwd()

  handle_dir_change(dir, function()
    local s_now = state.get()

    -- Not alive: start new instance
    if not s_now.handle or not adapter:is_alive(s_now.handle) then
      local should_reveal = opts.reveal ~= nil and opts.reveal or (opts.reveal == nil and config.get().auto_reveal)
      local current_file = should_reveal and vim.api.nvim_buf_get_name(0) or nil
      start_instance(target_mode, dir, current_file)
      return
    end

    -- Currently visible
    if adapter:is_visible(s_now.handle) then
      if s_now.mode == target_mode then
        -- Same mode: hide
        adapter:close(s_now.handle)
        s_now.mode = nil
      else
        -- Different mode: switch
        adapter:close(s_now.handle)
        local cfg = config.get()
        if target_mode == "float" then
          s_now.prev_win = vim.api.nvim_get_current_win()
        end
        adapter:show(
          s_now.handle,
          target_mode,
          { side = cfg.side, width = cfg.width, float = cfg.float, on_exit = function() end, on_ready = function() end }
        )
        s_now.mode = target_mode
        if target_mode == "float" then
          M._setup_float_auto_close()
        end
        adapter:focus(s_now.handle)
      end
      return
    end

    -- Alive but hidden: show
    local cfg = config.get()
    if target_mode == "float" then
      s_now.prev_win = vim.api.nvim_get_current_win()
    end
    adapter:show(
      s_now.handle,
      target_mode,
      { side = cfg.side, width = cfg.width, float = cfg.float, on_exit = function() end, on_ready = function() end }
    )
    s_now.mode = target_mode
    if target_mode == "float" then
      M._setup_float_auto_close()
    end
    adapter:focus(s_now.handle)
  end)
end

--- Show and focus trev (does not toggle).
--- @param opts? { position?: trev.Position, dir?: string, reveal?: boolean, reveal_path?: string }
function M.focus(opts)
  opts = opts or {}
  local s = state.get()
  local target_mode = opts.position or "panel"
  local dir = opts.dir or s.dir or vim.fn.getcwd()

  handle_dir_change(dir, function()
    local s_now = state.get()

    -- Not alive: start new instance
    if not s_now.handle or not adapter:is_alive(s_now.handle) then
      local should_reveal = opts.reveal ~= nil and opts.reveal or (opts.reveal == nil and config.get().auto_reveal)
      local reveal_path = opts.reveal_path or (should_reveal and vim.api.nvim_buf_get_name(0) or nil)
      start_instance(target_mode, dir, reveal_path)
      return
    end

    -- Reveal via IPC if requested (already running)
    if opts.reveal_path or opts.reveal then
      M.reveal(opts.reveal_path)
    end

    -- Visible
    if adapter:is_visible(s_now.handle) then
      if s_now.mode == target_mode then
        -- Same mode: just focus
        adapter:focus(s_now.handle)
      else
        -- Different mode: switch
        adapter:close(s_now.handle)
        local cfg = config.get()
        if target_mode == "float" then
          s_now.prev_win = vim.api.nvim_get_current_win()
        end
        adapter:show(
          s_now.handle,
          target_mode,
          { side = cfg.side, width = cfg.width, float = cfg.float, on_exit = function() end, on_ready = function() end }
        )
        s_now.mode = target_mode
        adapter:focus(s_now.handle)
      end
      return
    end

    -- Hidden: show + focus
    local cfg = config.get()
    if target_mode == "float" then
      s_now.prev_win = vim.api.nvim_get_current_win()
    end
    adapter:show(
      s_now.handle,
      target_mode,
      { side = cfg.side, width = cfg.width, float = cfg.float, on_exit = function() end, on_ready = function() end }
    )
    s_now.mode = target_mode
    adapter:focus(s_now.handle)
  end)
end

--- Show trev without moving focus.
--- @param opts? { position?: trev.Position, dir?: string, reveal?: boolean }
function M.show(opts)
  opts = opts or {}
  local s = state.get()
  local target_mode = opts.position or "panel"
  local dir = opts.dir or s.dir or vim.fn.getcwd()

  handle_dir_change(dir, function()
    local s_now = state.get()

    -- Not alive: start new instance (will get focus due to terminal)
    if not s_now.handle or not adapter:is_alive(s_now.handle) then
      local should_reveal = opts.reveal ~= nil and opts.reveal or (opts.reveal == nil and config.get().auto_reveal)
      local current_file = should_reveal and vim.api.nvim_buf_get_name(0) or nil
      start_instance(target_mode, dir, current_file)
      return
    end

    -- Already visible in same mode: no-op
    if adapter:is_visible(s_now.handle) and s_now.mode == target_mode then
      return
    end

    -- Close existing window if visible in different mode
    if adapter:is_visible(s_now.handle) then
      adapter:close(s_now.handle)
    end

    -- Show in target mode
    local cfg = config.get()
    if target_mode == "float" then
      s_now.prev_win = vim.api.nvim_get_current_win()
    end
    adapter:show(
      s_now.handle,
      target_mode,
      { side = cfg.side, width = cfg.width, float = cfg.float, on_exit = function() end, on_ready = function() end }
    )
    s_now.mode = target_mode
    if target_mode == "float" then
      M._setup_float_auto_close()
    end
  end)
end

--- Close/hide trev window (keep process alive).
function M.close()
  local s = state.get()
  if not s.handle or not adapter then
    return
  end
  require("trev.preview").hide()
  if adapter:is_visible(s.handle) then
    adapter:close(s.handle)
  end
  s.mode = nil
end

--- Reveal a file in trev's tree.
--- @param path? string file path (default: current buffer)
--- @param callback? fun(ok: boolean)
function M.reveal(path, callback)
  if not ipc.is_connected() then
    if callback then
      callback(false)
    end
    return
  end

  path = path or vim.api.nvim_buf_get_name(0)
  if not path or path == "" then
    if callback then
      callback(false)
    end
    return
  end

  if callback then
    ipc.send_request("reveal", { path = path }, function(result, err)
      if err then
        callback(false)
      else
        callback(result and result.ok or false)
      end
    end)
  else
    ipc.send_notification("reveal", { path = path })
  end
end

--- Quit trev (graceful shutdown).
function M.quit()
  local s = state.get()
  if not s.handle then
    return
  end

  if ipc.is_connected() then
    ipc.send_request("quit", nil, function()
      ipc.disconnect()
    end)
  elseif s.handle.job_id then
    pcall(vim.fn.jobstop, s.handle.job_id)
  end
end

--- Full cleanup (called from VimLeavePre).
function M._cleanup()
  local s = state.get()

  -- Send quit if connected
  if ipc.is_connected() then
    -- Synchronous-ish quit: send and immediately disconnect
    ipc.send_request("quit", nil, nil)
    ipc.disconnect()
  end

  -- Close preview overlay
  require("trev.preview").hide()

  -- Force stop if still running
  if s.handle and s.handle.job_id then
    pcall(vim.fn.jobstop, s.handle.job_id)
  end

  -- Clean up temp file
  if s.override_path then
    os.remove(s.override_path)
  end

  -- Clean up augroup
  if s.augroup then
    pcall(vim.api.nvim_del_augroup_by_id, s.augroup)
  end

  state.reset()
end

return M
