--- Predefined actions for trev keybindings.
--- Each action is a function that returns a trev.Action table.
--- Call without args for defaults, or pass overrides.
---
--- Usage:
---   actions.open()                              -- default
---   actions.open({ context = { "universal" } }) -- override context

--- @param base trev.Action
--- @return fun(overrides?: table): trev.Action
local function define_action(base)
  return function(overrides)
    if not overrides then
      return base
    end
    return vim.tbl_deep_extend("force", {}, base, overrides)
  end
end

local M = {}

--- Open file in Neovim.
M.open = define_action({
  _trev_action = true,
  _type = "notify",
  _value = "open_file",
  description = "Open file",
  context = { "file" },
})

--- Toggle directory expand/collapse.
M.toggle_expand = define_action({
  _trev_action = true,
  _type = "action",
  _value = "tree.toggle_expand",
  description = "Toggle expand",
  context = { "directory" },
})

--- Quit trev.
M.quit = define_action({
  _trev_action = true,
  _type = "action",
  _value = "quit",
  description = "Quit",
  context = { "universal" },
})

return M
