local M = {}

--- Resolve adapter by name.
--- @param adapter_name string
--- @return trev.Adapter
function M.resolve(adapter_name)
  if adapter_name == "native" then
    return require("trev.adapter.native").new()
  end

  vim.notify("[trev] Unknown adapter: " .. adapter_name .. ", falling back to native", vim.log.levels.WARN)
  return require("trev.adapter.native").new()
end

return M
