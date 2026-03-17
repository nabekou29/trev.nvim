--- Experimental: Treesitter-highlighted preview overlay.
--- Overlays a Neovim window on top of trev's built-in preview area
--- to provide syntax highlighting via treesitter and diagnostics.
--- Always uses scratch buffers to avoid rendering issues with
--- background transparency in editor windows.
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

--- @class trev.PreviewState
--- @field buf number|nil preview buffer (scratch)
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

--- Check if a file is an image that snacks can render.
--- Uses snacks.image config if available, otherwise falls back to common formats.
--- @param path string
--- @return boolean
local function is_image_file(path)
  local ext = path:match("%.(%w+)$")
  if not ext then
    return false
  end
  ext = ext:lower()

  -- Use snacks.image configured formats if available
  local ok, snacks_image = pcall(require, "snacks.image")
  if ok and snacks_image.config and snacks_image.config.formats then
    for _, fmt in ipairs(snacks_image.config.formats) do
      if fmt == ext then
        return true
      end
    end
    return false
  end

  -- Fallback
  local image_exts = { "png", "jpg", "jpeg", "gif", "bmp", "webp", "tiff", "heic", "avif", "ico", "icns" }
  for _, e in ipairs(image_exts) do
    if e == ext then
      return true
    end
  end
  return false
end

--- Create a scratch buffer with file content and treesitter highlighting.
--- Copies diagnostics from the real buffer if it's already loaded.
--- For binary/image files, creates an empty buffer (snacks handles rendering).
--- @param path string
--- @return number|nil buf
local function create_preview_buf(path)
  local buf = vim.api.nvim_create_buf(false, true)
  vim.bo[buf].bufhidden = "wipe"

  if not is_image_file(path) then
    local ok, lines = pcall(vim.fn.readfile, path)
    if not ok or not lines or #lines == 0 then
      vim.api.nvim_buf_delete(buf, { force = true })
      return nil
    end

    -- Sanitize lines: remove embedded newlines that nvim_buf_set_lines rejects
    for i, line in ipairs(lines) do
      if line:find("\n") then
        lines[i] = line:gsub("\n", "")
      end
    end

    vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
    vim.bo[buf].modifiable = false

    -- Detect filetype and apply syntax highlighting
    local ft = vim.filetype.match({ filename = path, buf = buf })
    if ft then
      vim.bo[buf].filetype = ft
      if not pcall(vim.treesitter.start, buf, ft) then
        vim.bo[buf].syntax = ft
      end
    end

    -- Copy diagnostics from the real buffer if it exists
    local real_buf = vim.fn.bufnr(path)
    if real_buf ~= -1 and vim.api.nvim_buf_is_loaded(real_buf) then
      local diagnostics = vim.diagnostic.get(real_buf)
      if #diagnostics > 0 then
        local ns = vim.api.nvim_create_namespace("trev_preview_diagnostics")
        vim.diagnostic.set(ns, buf, diagnostics)
      end
    end
  end

  return buf
end

--- Release the current preview buffer.
local function release_buf()
  if preview.buf and vim.api.nvim_buf_is_valid(preview.buf) then
    -- Clean snacks image placements before deleting
    pcall(function()
      require("snacks.image.placement").clean(preview.buf)
    end)
    vim.api.nvim_buf_delete(preview.buf, { force = true })
  end
  preview.buf = nil
end

--- Show or update the preview overlay.
--- @param path string file path to preview
--- @param area { win: number, x: number, y: number, width: number, height: number, scroll: number }
function M.show(path, area)
  local buf_changed = preview.path ~= path

  -- Create new scratch buffer when path changes
  if buf_changed then
    release_buf()
    preview.path = path

    local buf = create_preview_buf(path)
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

  -- When buffer changes, close and recreate window
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
    vim.wo[preview.win].winhighlight = "Normal:NormalFloat,SignColumn:NormalFloat"
    vim.o.eventignore = ei
  end

  -- Attach snacks image rendering for image files
  if buf_changed and is_image_file(path) then
    pcall(function()
      require("snacks.image.buf").attach(preview.buf, { src = path })
    end)
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
  if preview.win and vim.api.nvim_win_is_valid(preview.win) then
    vim.api.nvim_win_close(preview.win, true)
  end
  preview.win = nil
  preview.path = nil
  release_buf()
end

return M
