--- Experimental: Treesitter-highlighted preview overlay.
--- Overlays a Neovim window on top of trev's built-in preview area
--- to provide syntax highlighting via treesitter and diagnostics.
--- Uses bufadd/bufload to properly load buffers, enabling LSP
--- attachment and diagnostic display.
--- Supports image preview via snacks.image when available.
---
--- Expected IPC notification from trev:
---   method: "preview"
---   params:
---     path: string|nil  - file to preview (nil/empty to hide)
---     x: number         - column offset in trev terminal (0-indexed)
---     y: number         - row offset in trev terminal (0-indexed)
---     width: number     - preview area width (columns)
---     height: number    - preview area height (rows)
---     scroll: number?   - first visible line (0-indexed, default 0)

local state = require("trev.state")

local M = {}

--- Clean image placements on a buffer and re-attach for new content.
--- Mirrors snacks picker behavior: clean old placements, then attach new.
--- @param buf number buffer to clean
local function clean_image_placements(buf)
  pcall(function()
    require("snacks.image.placement").clean(buf)
  end)
end

--- Re-attach snacks image rendering on a buffer.
--- @param buf number buffer to attach
local function attach_image(buf)
  pcall(function()
    require("snacks.image.buf").attach(buf)
  end)
end

--- @class trev.PreviewState
--- @field buf number|nil preview buffer
--- @field win number|nil preview floating window
--- @field path string|nil currently previewed file path

--- @type trev.PreviewState
local preview = {
  buf = nil,
  win = nil,
  path = nil,
}

--- Handle preview notification from trev.
--- @param params table
function M.on_preview(params)
  local s = state.get()

  -- No trev window to overlay on
  if not s.handle or not s.handle.win or not vim.api.nvim_win_is_valid(s.handle.win) then
    M.hide()
    return
  end

  -- Hide preview (only show for Neovim provider)
  if not params.path or params.path == "" or params.provider ~= "Neovim" then
    M.hide()
    return
  end

  M.show(params.path, {
    win = s.handle.win,
    x = params.x or 0,
    y = params.y or 0,
    width = params.width or 40,
    height = params.height or 20,
    scroll = params.scroll or 0,
  })
end

--- Resolve a buffer for the given file path.
--- Uses bufadd/bufload to properly load the buffer, enabling LSP and diagnostics.
--- @param path string
--- @return number|nil buf
local function resolve_buf(path)
  -- Suppress autocmds to prevent auto-reveal interference
  local ei = vim.o.eventignore
  vim.o.eventignore = "BufEnter,BufWinEnter,BufLeave,WinEnter,WinLeave"

  local buf = vim.fn.bufadd(path)
  if buf == 0 then
    vim.o.eventignore = ei
    return nil
  end

  if not vim.api.nvim_buf_is_loaded(buf) then
    vim.fn.bufload(buf)
  end

  -- Keep out of buffer list
  vim.bo[buf].buflisted = false

  vim.o.eventignore = ei
  return buf
end

--- Show or update the preview overlay.
--- @param path string file path to preview
--- @param area { win: number, x: number, y: number, width: number, height: number, scroll: number }
function M.show(path, area)
  local buf_changed = preview.path ~= path

  -- Resolve buffer when path changes
  if buf_changed then
    -- Clean old image placements before switching
    if preview.buf and vim.api.nvim_buf_is_valid(preview.buf) then
      clean_image_placements(preview.buf)
    end

    preview.path = path

    local buf = resolve_buf(path)
    if not buf then
      M.hide()
      return
    end
    preview.buf = buf
  end

  -- Guard: buffer may have been wiped externally
  if not preview.buf or not vim.api.nvim_buf_is_valid(preview.buf) then
    M.hide()
    return
  end

  -- Offset by 1 on each side to account for trev's preview border
  local trev_width = vim.api.nvim_win_get_width(area.win)
  local trev_height = vim.api.nvim_win_get_height(area.win)
  local col = math.min(area.x + 1, math.max(0, trev_width - 1))
  local row = math.min(area.y + 1, math.max(0, trev_height - 1))
  local width = math.max(1, math.min(area.width - 2, trev_width - col))
  local height = math.max(1, math.min(area.height - 2, trev_height - row))

  -- Window config: overlay on trev window
  local win_config = {
    relative = "win",
    win = area.win,
    row = row,
    col = col,
    width = width,
    height = height,
    border = "none",
    focusable = false,
    zindex = 250,
  }

  -- When buffer changes, close and recreate window so snacks can
  -- properly clean up old image placements tied to the window.
  if buf_changed and preview.win and vim.api.nvim_win_is_valid(preview.win) then
    vim.api.nvim_win_close(preview.win, true)
    preview.win = nil
  end

  if preview.win and vim.api.nvim_win_is_valid(preview.win) then
    vim.api.nvim_win_set_config(preview.win, win_config)
  else
    preview.win = vim.api.nvim_open_win(preview.buf, false, win_config)
    -- Suppress OptionSet autocmds to avoid errors from other plugins
    local ei = vim.o.eventignore
    vim.o.eventignore = "OptionSet"
    vim.wo[preview.win].number = true
    vim.wo[preview.win].relativenumber = false
    vim.wo[preview.win].signcolumn = "yes"
    vim.wo[preview.win].foldcolumn = "0"
    vim.wo[preview.win].wrap = false
    vim.wo[preview.win].cursorline = false
    vim.wo[preview.win].colorcolumn = ""
    vim.wo[preview.win].list = false
    vim.wo[preview.win].winblend = 0
    vim.wo[preview.win].winhighlight = "Normal:TrevPreview,SignColumn:TrevPreview"
    vim.o.eventignore = ei

    -- Ensure TrevPreview has an opaque background
    local normal_hl = vim.api.nvim_get_hl(0, { name = "Normal" })
    local float_hl = vim.api.nvim_get_hl(0, { name = "NormalFloat" })
    local bg = (normal_hl and normal_hl.bg) or (float_hl and float_hl.bg) or 0x1a1a1a
    local fg = (normal_hl and normal_hl.fg) or (float_hl and float_hl.fg)
    vim.api.nvim_set_hl(0, "TrevPreview", { fg = fg, bg = bg })
  end

  -- Re-attach snacks image rendering for image files
  if buf_changed then
    attach_image(preview.buf)
  end

  -- Scroll to position
  local line_count = vim.api.nvim_buf_line_count(preview.buf)
  local target_line = math.min(area.scroll + 1, line_count)
  pcall(vim.api.nvim_win_set_cursor, preview.win, { target_line, 0 })
  if area.scroll > 0 then
    vim.api.nvim_win_call(preview.win, function()
      vim.cmd("normal! zt")
    end)
  end
end

--- Hide the preview overlay.
function M.hide()
  -- Clean image placements before closing
  if preview.buf and vim.api.nvim_buf_is_valid(preview.buf) then
    clean_image_placements(preview.buf)
  end
  if preview.win and vim.api.nvim_win_is_valid(preview.win) then
    vim.api.nvim_win_close(preview.win, true)
  end
  preview.win = nil
  preview.path = nil
  preview.buf = nil
end

return M
