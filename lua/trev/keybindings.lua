local M = {}

local KB_METHOD_PREFIX = "nvim._kb."

--- Check if a value is a predefined trev.Action.
--- @param v any
--- @return boolean
local function is_action(v)
  return type(v) == "table" and v._trev_action == true
end

--- Normalize keybindings config into a flat list of BindingEntry.
--- Handles trev.Action, trev.Action[], and trev.KeybindingDef.
--- @param keybindings table<string, trev.KeybindingValue>
--- @return trev.BindingEntry[]
function M.normalize(keybindings)
  local entries = {}

  for key, value in pairs(keybindings) do
    if is_action(value) then
      -- Single predefined action
      --- @cast value trev.Action
      for _, ctx in ipairs(value.context) do
        table.insert(entries, {
          key = key,
          type = value._type,
          value = value._value,
          context = ctx,
        })
      end
    elseif type(value) == "table" and #value > 0 and is_action(value[1]) then
      -- List of predefined actions
      for _, action in ipairs(value) do
        --- @cast action trev.Action
        for _, ctx in ipairs(action.context) do
          table.insert(entries, {
            key = key,
            type = action._type,
            value = action._value,
            context = ctx,
          })
        end
      end
    else
      -- Custom KeybindingDef with callback
      --- @cast value trev.KeybindingDef
      local method = KB_METHOD_PREFIX .. key
      local contexts = value.context or { "file" }
      for _, ctx in ipairs(contexts) do
        table.insert(entries, {
          key = key,
          type = "notify",
          value = method,
          context = ctx,
          callback = value.action,
          description = value.description,
        })
      end
    end
  end

  return entries
end

--- Register Neovim-side handlers for callback-type entries.
--- @param entries trev.BindingEntry[]
--- @param handlers table<string, fun(params: table)>
function M.register_handlers(entries, handlers)
  -- Deduplicate by value (same callback method may appear in multiple contexts)
  local registered = {}
  for _, entry in ipairs(entries) do
    if entry.callback and not registered[entry.value] then
      registered[entry.value] = true
      local cb = entry.callback
      handlers[entry.value] = function(params)
        --- @type trev.KeybindingEvent
        local event = {
          current_file = params.path or "",
          dir = params.dir or "",
          name = params.name or "",
          root = params.root or "",
          is_dir = params.is_dir or false,
        }
        cb(event)
      end
    end
  end
end

--- Generate override YAML content for trev's --config-override.
--- @param entries trev.BindingEntry[]
--- @return string yaml content
function M.generate_yaml(entries)
  if #entries == 0 then
    return ""
  end

  -- Group by context
  --- @type table<string, trev.BindingEntry[]>
  local by_context = {}
  for _, entry in ipairs(entries) do
    if not by_context[entry.context] then
      by_context[entry.context] = {}
    end
    table.insert(by_context[entry.context], entry)
  end

  local lines = {}
  table.insert(lines, "keybindings:")
  table.insert(lines, "  daemon:")

  local contexts = vim.tbl_keys(by_context)
  table.sort(contexts)

  for _, ctx in ipairs(contexts) do
    local bindings = by_context[ctx]
    table.insert(lines, "    " .. ctx .. ":")
    table.insert(lines, "      bindings:")
    for _, b in ipairs(bindings) do
      table.insert(lines, '        - key: "' .. b.key .. '"')
      if b.type == "notify" then
        table.insert(lines, "          notify: " .. b.value)
      elseif b.type == "action" then
        table.insert(lines, "          action: " .. b.value)
      end
    end
  end

  -- custom_actions for callback-type entries
  local has_custom = false
  for _, entry in ipairs(entries) do
    if entry.callback then
      if not has_custom then
        table.insert(lines, "")
        table.insert(lines, "custom_actions:")
        has_custom = true
      end
      local desc = entry.description or ("(nvim: " .. entry.key .. ")")
      table.insert(lines, "  " .. entry.value .. ":")
      table.insert(lines, '    description: "' .. desc:gsub('"', '\\"') .. '"')
      table.insert(lines, "    notify: " .. entry.value)
    end
  end

  return table.concat(lines, "\n") .. "\n"
end

--- Write override YAML to a temp file and return the path.
--- @param entries trev.BindingEntry[]
--- @return string|nil path to temp file
function M.write_override_file(entries)
  if #entries == 0 then
    return nil
  end

  local yaml = M.generate_yaml(entries)
  local tmpfile = os.tmpname()
  local f = io.open(tmpfile, "w")
  if not f then
    vim.notify("[trev] Failed to create override file", vim.log.levels.ERROR)
    return nil
  end
  f:write(yaml)
  f:close()
  return tmpfile
end

return M
