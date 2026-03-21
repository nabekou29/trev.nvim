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

local MAX_FILE_SIZE = 1024 * 1024 -- 1 MB
local MAX_LINES = 5000
local DEBOUNCE_MS = 16

--- @class trev.PreviewState
--- @field buf number|nil preview buffer
--- @field win number|nil preview floating window
--- @field path string|nil currently previewed file path
--- @field owns_buf boolean whether we created a scratch buffer
--- @field pending_timer userdata|nil debounce timer
--- @field trev_active boolean whether trev is showing a preview (any provider)

--- @type trev.PreviewState
local preview = {
  buf = nil,
  win = nil,
  path = nil,
  owns_buf = false,
  pending_timer = nil,
  trev_active = false,
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

  preview.trev_active = params.path ~= nil and params.path ~= ""

  -- Hide preview (only show for Neovim provider)
  if not preview.trev_active or params.provider ~= "Neovim" then
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
--- @param path string
--- @return boolean
local function is_image_file(path)
  local ext = path:match("%.(%w+)$")
  if not ext then
    return false
  end
  ext = ext:lower()

  local ok, snacks_image = pcall(require, "snacks.image")
  if ok and snacks_image.config and snacks_image.config.formats then
    for _, fmt in ipairs(snacks_image.config.formats) do
      if fmt == ext then
        return true
      end
    end
    return false
  end

  local image_exts = { "png", "jpg", "jpeg", "gif", "bmp", "webp", "tiff", "heic", "avif", "ico", "icns" }
  for _, e in ipairs(image_exts) do
    if e == ext then
      return true
    end
  end
  return false
end

--- Try to find an already-loaded buffer for the path.
--- Does NOT call bufadd/bufload to avoid transparency side effects.
--- @param path string
--- @return number|nil buf
local function find_loaded_buf(path)
  local existing = vim.fn.bufnr(path)
  if existing ~= -1 and vim.api.nvim_buf_is_loaded(existing) then
    return existing
  end
  return nil
end

--- Load file content into the preview scratch buffer.
--- @param buf number scratch buffer
--- @param path string file path
--- @return boolean success
local function load_file_content(buf, path)
  -- Check file size
  local stat = vim.uv.fs_stat(path)
  if not stat then
    return false
  end
  if stat.size > MAX_FILE_SIZE then
    vim.api.nvim_buf_set_lines(buf, 0, -1, false, { "(file too large to preview)" })
    vim.bo[buf].modifiable = false
    return true
  end

  local ok, lines = pcall(vim.fn.readfile, path, "", MAX_LINES)
  if not ok or not lines or #lines == 0 then
    return false
  end

  -- Sanitize: remove embedded newlines that nvim_buf_set_lines rejects
  for i, line in ipairs(lines) do
    if line:find("\n") then
      lines[i] = line:gsub("\n", "")
    end
  end

  vim.bo[buf].modifiable = true
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

  return true
end

--- Reset the scratch buffer for new content.
--- @param buf number
local function reset_buf(buf)
  if not vim.api.nvim_buf_is_valid(buf) then
    return
  end
  pcall(vim.treesitter.stop, buf)
  vim.api.nvim_buf_clear_namespace(buf, -1, 0, -1)
  vim.bo[buf].modifiable = true
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, {})
  vim.bo[buf].filetype = ""
  vim.bo[buf].syntax = ""
end

--- Ensure the scratch buffer exists, creating it if needed.
--- @return number buf
local function ensure_buf()
  if preview.buf and vim.api.nvim_buf_is_valid(preview.buf) then
    return preview.buf
  end
  local buf = vim.api.nvim_create_buf(false, true)
  vim.bo[buf].bufhidden = "hide"
  preview.buf = buf
  return buf
end

--- Clean up image placements on the preview buffer.
local function clean_images()
  if not preview.buf or not vim.api.nvim_buf_is_valid(preview.buf) then
    return
  end
  pcall(function()
    require("snacks.image.placement").clean(preview.buf)
  end)
end

--- Release the preview buffer if we own it (scratch).
local function release_buf()
  if preview.buf and vim.api.nvim_buf_is_valid(preview.buf) and preview.owns_buf then
    vim.api.nvim_buf_delete(preview.buf, { force = true })
  end
  preview.buf = nil
  preview.owns_buf = false
end

--- Ensure the preview window exists with the given config.
--- @param win_config table
local function ensure_win(win_config)
  if preview.win and vim.api.nvim_win_is_valid(preview.win) then
    vim.api.nvim_win_set_config(preview.win, win_config)
    -- Swap buffer if needed
    if vim.api.nvim_win_get_buf(preview.win) ~= preview.buf then
      vim.api.nvim_win_set_buf(preview.win, preview.buf)
    end
    return
  end

  preview.win = vim.api.nvim_open_win(preview.buf, false, win_config)
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

--- Cancel any pending debounced preview update.
local function cancel_pending()
  if preview.pending_timer and not preview.pending_timer:is_closing() then
    preview.pending_timer:stop()
    preview.pending_timer:close()
  end
  preview.pending_timer = nil
end

--- Load content and apply highlighting (called after debounce).
--- @param path string
--- @param is_image boolean
local function apply_content(path, is_image)
  if not preview.buf or not vim.api.nvim_buf_is_valid(preview.buf) then
    return
  end
  -- Ensure this is still the current path (not stale)
  if preview.path ~= path then
    return
  end

  if is_image then
    pcall(function()
      require("snacks.image.buf").attach(preview.buf, { src = path })
    end)
  else
    load_file_content(preview.buf, path)
  end
end

--- Show or update the preview overlay.
--- @param path string file path to preview
--- @param area { win: number, x: number, y: number, width: number, height: number, scroll: number }
function M.show(path, area)
  local buf_changed = preview.path ~= path

  if buf_changed then
    cancel_pending()
    clean_images()
    release_buf()
    preview.path = path

    -- Try to use already-loaded buffer directly (diagnostics, LSP, etc.)
    local loaded = find_loaded_buf(path)
    if loaded then
      preview.buf = loaded
      preview.owns_buf = false
    else
      local buf = ensure_buf()
      reset_buf(buf)
      preview.owns_buf = true

      -- Debounce content loading to avoid treesitter race conditions
      local is_image = is_image_file(path)
      local timer = vim.uv.new_timer()
      preview.pending_timer = timer
      timer:start(DEBOUNCE_MS, 0, vim.schedule_wrap(function()
        if timer == preview.pending_timer then
          preview.pending_timer = nil
        end
        if not timer:is_closing() then
          timer:close()
        end
        apply_content(path, is_image)
      end))
    end
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

  local s = state.get()
  local zindex = (s.mode == "float") and 100 or 1

  ensure_win({
    relative = "win",
    win = area.win,
    row = row,
    col = col,
    width = width,
    height = height,
    border = "none",
    focusable = false,
    zindex = zindex,
  })

  -- Scroll to position (for non-debounced updates like scroll changes)
  if not buf_changed then
    local line_count = vim.api.nvim_buf_line_count(preview.buf)
    local target_line = math.min(area.scroll + 1, line_count)
    pcall(vim.api.nvim_win_set_cursor, preview.win, { target_line, 0 })
    if area.scroll > 0 then
      vim.api.nvim_win_call(preview.win, function()
        vim.cmd("normal! zt")
      end)
    end
  end
end

--- Check if trev is showing a preview (any provider).
--- @return boolean
function M.is_trev_active()
  return preview.trev_active
end

--- Hide the preview overlay.
function M.hide()
  cancel_pending()
  clean_images()
  if preview.win and vim.api.nvim_win_is_valid(preview.win) then
    vim.api.nvim_win_close(preview.win, true)
  end
  preview.win = nil
  preview.path = nil
  preview.trev_active = false
  release_buf()
end

return M
