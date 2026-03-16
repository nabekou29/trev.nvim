--- LuaCATS type definitions for trev.nvim
--- This module contains only annotations and returns an empty table.

--- @alias trev.Position "panel" | "float"
--- @alias trev.Side "left" | "right"
--- @alias trev.OpenAction "edit" | "split" | "vsplit" | "tabedit"

--- @class trev.Config
--- @field trev_path string trev binary path
--- @field side trev.Side panel side ("left" or "right")
--- @field width number side panel width (columns)
--- @field float trev.FloatConfig floating window config
--- @field auto_reveal boolean auto reveal on BufEnter
--- @field default_keybindings boolean enable default keybindings
--- @field adapter string terminal backend ("native")
--- @field handlers table<string, fun(params: table)> custom notification handlers
--- @field keybindings table<string, trev.KeybindingValue|false> keybinding definitions (false to disable)

--- @class trev.FloatConfig
--- @field width number fraction of editor width (0.0-1.0) or absolute columns
--- @field height number fraction of editor height (0.0-1.0) or absolute rows

--- @class trev.UserConfig
--- @field trev_path? string
--- @field side? trev.Side
--- @field width? number
--- @field float? trev.FloatConfig
--- @field auto_reveal? boolean
--- @field default_keybindings? boolean
--- @field adapter? string
--- @field handlers? table<string, fun(params: table)>
--- @field keybindings? table<string, trev.KeybindingValue|false>

--- @class trev.State
--- @field handle trev.AdapterHandle|nil terminal handle
--- @field mode trev.Position|nil current display mode
--- @field dir string|nil current workspace directory
--- @field prev_win number|nil window ID before float
--- @field pipe userdata|nil vim.uv pipe handle
--- @field socket_path string|nil connected socket path
--- @field read_buf string receive buffer for line framing
--- @field request_id number next JSON-RPC request ID
--- @field pending table<number, fun(result: any, error: any)> pending request callbacks
--- @field override_path string|nil temp YAML file path
--- @field augroup number|nil auto-reveal augroup ID

--- @class trev.Adapter
--- @field open_panel fun(self: trev.Adapter, cmd: string[], opts: trev.AdapterOpts): trev.AdapterHandle|nil
--- @field open_float fun(self: trev.Adapter, cmd: string[], opts: trev.AdapterOpts): trev.AdapterHandle|nil
--- @field close fun(self: trev.Adapter, handle: trev.AdapterHandle)
--- @field show fun(self: trev.Adapter, handle: trev.AdapterHandle, mode: trev.Position, opts: trev.AdapterOpts)
--- @field is_visible fun(self: trev.Adapter, handle: trev.AdapterHandle): boolean
--- @field is_alive fun(self: trev.Adapter, handle: trev.AdapterHandle): boolean
--- @field focus fun(self: trev.Adapter, handle: trev.AdapterHandle)

--- @class trev.AdapterOpts
--- @field side? trev.Side panel side
--- @field width? number panel width
--- @field float? trev.FloatConfig float dimensions
--- @field on_exit fun(exit_code: number)
--- @field on_ready fun(handle: trev.AdapterHandle)

--- @class trev.AdapterHandle
--- @field buf number|nil Neovim buffer number
--- @field win number|nil Neovim window number
--- @field pid number|nil process ID
--- @field job_id number|nil Neovim job ID

--- @class trev.KeybindingDef
--- @field description? string
--- @field action fun(e: trev.KeybindingEvent)
--- @field context? string[] contexts ("file", "directory", "universal")

--- Keybinding config value: a single Action, list of Actions, or a custom KeybindingDef
--- @alias trev.KeybindingValue trev.Action | trev.Action[] | trev.KeybindingDef

--- Normalized binding entry for YAML generation
--- @class trev.BindingEntry
--- @field key string
--- @field type "notify"|"action" notify = IPC to Neovim, action = trev internal
--- @field value string method name or trev action name
--- @field context string
--- @field description? string
--- @field callback? fun(e: trev.KeybindingEvent) only for user-defined callbacks

--- @class trev.KeybindingEvent
--- @field current_file string absolute path of cursor position
--- @field dir string directory path
--- @field name string basename
--- @field root string workspace root
--- @field is_dir boolean

--- @class trev.CommandOpts
--- @field action? "focus" | "show" | "close" | "reveal" | "quit"
--- @field position? trev.Position
--- @field dir? string
--- @field reveal_path? string

return {}
