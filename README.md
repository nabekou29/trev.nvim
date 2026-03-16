# trev.nvim

[日本語](README.ja.md)

Neovim plugin for [trev](https://github.com/nabekou29/trev) — a fast file tree explorer.

For detailed information about trev itself (features, installation, configuration of the daemon), please refer to the [trev repository](https://github.com/nabekou29/trev).

## Requirements

- Neovim
- [trev](https://github.com/nabekou29/trev)

## Installation

Using [lazy.nvim](https://github.com/folke/lazy.nvim):

```lua
{
  "nabekou29/trev.nvim",
  opts = {},
}
```

## Configuration

```lua
require("trev").setup({
  -- Path to the trev binary
  trev_path = "trev",
  -- Side panel width (columns)
  width = 60,
  -- Floating window dimensions
  float = {
    width = 0.6,  -- fraction of editor width (0.0-1.0) or absolute columns
    height = 0.7, -- fraction of editor height (0.0-1.0) or absolute rows
  },
  -- Automatically reveal the current buffer in the tree on BufEnter
  auto_reveal = true,
  -- Keybinding definitions
  keybindings = {},
})
```

## Usage

### Command

```vim
:Trev [action] [position] [dir=path] [reveal=path]
```

| Action    | Description                 |
| --------- | --------------------------- |
| *(none)*  | Toggle visibility (default) |
| `focus`   | Show and focus the tree     |
| `show`    | Show without moving focus   |
| `close`   | Hide the tree               |
| `reveal`  | Reveal a file in the tree   |
| `quit`    | Shut down the trev daemon   |

| Position  | Description            |
| --------- | ---------------------- |
| *(none)*  | Panel mode (default)   |
| `float`   | Floating window mode   |

Examples:

```vim
:Trev                    " Toggle panel
:Trev float              " Toggle floating window
:Trev focus float        " Open and focus floating window
:Trev reveal=src/main.rs " Reveal a specific file
:Trev dir=~/projects/foo " Open tree for a specific directory
```

### Lua API

```lua
local trev = require("trev")

trev.toggle()                          -- Toggle panel
trev.toggle({ position = "float" })    -- Toggle floating window
trev.focus()                           -- Show and focus
trev.show()                            -- Show without focus
trev.close()                           -- Hide (keep daemon alive)
trev.reveal()                          -- Reveal current buffer in tree
trev.reveal("/path/to/file")           -- Reveal specific file
trev.quit()                            -- Shut down daemon
```

### Keymaps

```lua
vim.keymap.set("n", "<leader>e", function() require("trev").toggle() end)
vim.keymap.set("n", "<leader>E", function() require("trev").toggle({ position = "float" }) end)
```

## Keybindings

Keybindings define how keys work **inside the trev tree**.

### Predefined Actions

```lua
local actions = require("trev").actions

require("trev").setup({
  keybindings = {
    ["<CR>"] = actions.open(),
    ["e"] = actions.toggle_expand(),
    ["q"] = actions.quit(),
  },
})
```

| Action           | Description                    | Default Context |
| ---------------- | ------------------------------ | --------------- |
| `open`           | Open file in Neovim            | `file`          |
| `toggle_expand`  | Toggle directory expand/collapse | `directory`   |
| `quit`           | Quit trev                      | `universal`     |

### Custom Callbacks

```lua
require("trev").setup({
  keybindings = {
    ["<C-v>"] = {
      action = function(event)
        vim.cmd("vsplit " .. vim.fn.fnameescape(event.current_file))
      end,
      context = { "file" },
      description = "Open in vertical split",
    },
  },
})
```

The callback receives a `trev.KeybindingEvent`:

| Field          | Type    | Description              |
| -------------- | ------- | ------------------------ |
| `current_file` | string  | Absolute path of the item |
| `dir`          | string  | Directory path            |
| `name`         | string  | Basename                  |
| `root`         | string  | Workspace root            |
| `is_dir`       | boolean | Whether the item is a directory |

## License

[MIT](LICENSE)
