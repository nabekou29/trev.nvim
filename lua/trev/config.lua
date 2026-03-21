local M = {}

--- @type trev.Config
local defaults = {
  trev_path = "trev",
  args = {},
  side = "left",
  width = 60,
  float = {},
  auto_reveal = true,
  default_keybindings = true,
  adapter = "auto",
  neovim_preview = {
    enabled = true,
    priority = "high",
  },
  handlers = {},
  keybindings = {},
}

--- @type trev.Config|nil
M._config = nil

--- @param user_config? trev.UserConfig
--- @return trev.Config
function M.apply(user_config)
  M._config = vim.tbl_deep_extend("force", {}, defaults, user_config or {})
  M.validate(M._config)
  return M._config
end

--- @return trev.Config
function M.get()
  if not M._config then
    error("[trev] setup() has not been called")
  end
  return M._config
end

--- @param config trev.Config
function M.validate(config)
  vim.validate({
    trev_path = { config.trev_path, "string" },
    args = { config.args, "table" },
    side = { config.side, "string" },
    width = { config.width, "number" },
    float = { config.float, "table" },
    auto_reveal = { config.auto_reveal, "boolean" },
    default_keybindings = { config.default_keybindings, "boolean" },
    adapter = { config.adapter, "string" },
    handlers = { config.handlers, "table" },
    keybindings = { config.keybindings, "table" },
  })

  vim.validate({
    ["float.width"] = { config.float.width, { "number", "nil" } },
    ["float.height"] = { config.float.height, { "number", "nil" } },
  })
end

--- @return trev.Config
function M.defaults()
  return vim.deepcopy(defaults)
end

return M
