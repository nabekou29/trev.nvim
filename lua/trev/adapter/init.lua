local M = {}

--- Resolve adapter by name.
--- @param adapter_name string
--- @return trev.Adapter
--- @param mod string
--- @return boolean
local function has(mod)
  local loaded, _ = pcall(require, mod)
  return loaded
end

function M.resolve(adapter_name)
  if adapter_name == "auto" then
    if has("snacks") then
      return require("trev.adapter.snacks").new()
    elseif has("toggleterm") then
      return require("trev.adapter.toggleterm").new()
    end
    return require("trev.adapter.native").new()
  elseif adapter_name == "toggleterm" then
    return require("trev.adapter.toggleterm").new()
  elseif adapter_name == "snacks" then
    return require("trev.adapter.snacks").new()
  elseif adapter_name == "native" then
    return require("trev.adapter.native").new()
  end

  vim.notify("[trev] Unknown adapter: " .. adapter_name .. ", falling back to auto", vim.log.levels.WARN)
  return M.resolve("auto")
end

return M
