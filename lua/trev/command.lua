--- Command parser and registration for :Trev command.

local M = {}

--- Known action keywords
local ACTIONS = {
  focus = true,
  show = true,
  close = true,
  reveal = true,
  quit = true,
}

--- Known position keywords
local POSITIONS = {
  float = true,
}

--- Parse :Trev command arguments.
--- @param args string raw argument string
--- @return trev.CommandOpts
function M.parse(args)
  --- @type trev.CommandOpts
  local opts = {}

  for token in args:gmatch("%S+") do
    -- key=value pairs
    local key, value = token:match("^(%w+)=(.+)$")
    if key then
      if key == "dir" then
        opts.dir = vim.fn.expand(value)
      elseif key == "reveal" then
        opts.action = "reveal"
        opts.reveal_path = vim.fn.expand(value)
      end
    elseif ACTIONS[token] then
      opts.action = token
    elseif POSITIONS[token] then
      opts.position = token
    elseif token == "reveal" then
      opts.action = "reveal"
    end
  end

  return opts
end

--- Register the :Trev user command.
function M.register()
  vim.api.nvim_create_user_command("Trev", function(cmd_opts)
    local parsed = M.parse(cmd_opts.args)
    local trev = require("trev")

    local action = parsed.action

    if action == "close" then
      trev.close()
    elseif action == "quit" then
      trev.quit()
    elseif action == "reveal" then
      trev.focus({ position = parsed.position, dir = parsed.dir })
      trev.reveal(parsed.reveal_path)
    elseif action == "focus" then
      trev.focus({ position = parsed.position, dir = parsed.dir })
    elseif action == "show" then
      trev.show({ position = parsed.position, dir = parsed.dir })
    else
      -- Default: toggle
      trev.toggle({ position = parsed.position, dir = parsed.dir })
    end
  end, {
    nargs = "*",
    complete = function(_, cmdline, _)
      local args = cmdline:match("^Trev%s+(.*)$") or ""
      local tokens = {}
      for token in args:gmatch("%S+") do
        table.insert(tokens, token)
      end

      -- Suggest completions
      local suggestions = {}
      local has_action = false
      local has_position = false
      for _, token in ipairs(tokens) do
        if ACTIONS[token] then
          has_action = true
        end
        if POSITIONS[token] then
          has_position = true
        end
      end

      if not has_action then
        for action in pairs(ACTIONS) do
          table.insert(suggestions, action)
        end
      end
      if not has_position then
        for pos in pairs(POSITIONS) do
          table.insert(suggestions, pos)
        end
      end
      table.insert(suggestions, "dir=")
      table.insert(suggestions, "reveal=")

      table.sort(suggestions)
      return suggestions
    end,
  })
end

return M
