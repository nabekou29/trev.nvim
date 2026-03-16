# trev.nvim

[English](README.md)

[trev](https://github.com/nabekou29/trev) の Neovim プラグイン — 高速なファイルツリーエクスプローラー。

trev 本体の詳細（機能、インストール、デーモンの設定など）については [trev リポジトリ](https://github.com/nabekou29/trev) を参照してください。

## 必要要件

- Neovim
- [trev](https://github.com/nabekou29/trev)

## インストール

[lazy.nvim](https://github.com/folke/lazy.nvim) の場合:

```lua
{
  "nabekou29/trev.nvim",
  keys = {
    { "<leader>e", function() require("trev").show() end, desc = "Show trev" },
    { "<leader>E", function() require("trev").show({ position = "float" }) end, desc = "Show trev (float)" },
  },
  opts = {
    width = 60,
    keybindings = {
      -- chowcho.nvim を使ってウィンドウを選択してファイルを開く
      -- ["<S-CR>"] = {
      --   action = function(event)
      --     require("chowcho").run(function(winid)
      --       vim.api.nvim_set_current_win(winid)
      --       vim.cmd("edit " .. vim.fn.fnameescape(event.current_file))
      --     end)
      --   end,
      --   context = { "file" },
      --   description = "Open with window picker",
      -- },
    },
  },
}
```

## 設定

```lua
require("trev").setup({
  -- trev バイナリのパス
  trev_path = "trev",
  -- サイドパネルの幅（カラム数）
  width = 60,
  -- フローティングウィンドウのサイズ
  float = {
    width = 0.6,  -- エディタ幅に対する割合 (0.0-1.0) または絶対値
    height = 0.7, -- エディタ高さに対する割合 (0.0-1.0) または絶対値
  },
  -- BufEnter 時に現在のバッファをツリーで自動表示
  auto_reveal = true,
  -- デフォルトキーバインドを有効にする (<CR> = open, q = quit)
  default_keybindings = true,
  -- キーバインディング定義 (false を設定するとデフォルトを無効化)
  keybindings = {},
})
```

## 使い方

### コマンド

```vim
:Trev [action] [position] [dir=path] [reveal=path]
```

| Action    | 説明                          |
| --------- | ----------------------------- |
| *(なし)*  | 表示の切り替え（デフォルト）  |
| `focus`   | ツリーを表示してフォーカス    |
| `show`    | フォーカスを移動せず表示      |
| `close`   | ツリーを非表示にする          |
| `reveal`  | ツリー内でファイルを表示      |
| `quit`    | trev デーモンを終了           |

| Position  | 説明                           |
| --------- | ------------------------------ |
| *(なし)*  | パネルモード（デフォルト）     |
| `float`   | フローティングウィンドウモード |

例:

```vim
:Trev                    " パネルの切り替え
:Trev float              " フローティングウィンドウの切り替え
:Trev focus float        " フローティングウィンドウを開いてフォーカス
:Trev reveal=src/main.rs " 特定のファイルを表示
:Trev dir=~/projects/foo " 特定のディレクトリでツリーを開く
```

### Lua API

```lua
local trev = require("trev")

trev.toggle()                          -- パネルの切り替え
trev.toggle({ position = "float" })    -- フローティングウィンドウの切り替え
trev.focus()                           -- 表示してフォーカス
trev.show()                            -- フォーカスを移動せず表示
trev.close()                           -- 非表示（デーモンは維持）
trev.reveal()                          -- 現在のバッファをツリーで表示
trev.reveal("/path/to/file")           -- 特定のファイルをツリーで表示
trev.quit()                            -- デーモンを終了
```

### キーマップ

```lua
vim.keymap.set("n", "<leader>e", function() require("trev").show() end)
vim.keymap.set("n", "<leader>E", function() require("trev").show({ position = "float" }) end)
```

## キーバインディング

キーバインディングは **trev ツリー内** でのキー操作を定義します。

### デフォルトキーバインド

| キー   | アクション | 説明             |
| ------ | ---------- | ---------------- |
| `<CR>` | `open`     | ファイルを開く   |
| `q`    | `quit`     | trev を終了      |

デフォルトキーバインドを個別に無効化するには `false` を設定します:

```lua
require("trev").setup({
  keybindings = {
    ["q"] = false, -- デフォルトの quit を無効化
  },
})
```

すべてのデフォルトキーバインドを無効化するには:

```lua
require("trev").setup({
  default_keybindings = false,
})
```

### カスタムキーバインド

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

コールバックは `trev.KeybindingEvent` を受け取ります:

| フィールド     | 型      | 説明                         |
| -------------- | ------- | ---------------------------- |
| `current_file` | string  | アイテムの絶対パス           |
| `dir`          | string  | ディレクトリパス             |
| `name`         | string  | ベースネーム                 |
| `root`         | string  | ワークスペースルート         |
| `is_dir`       | boolean | ディレクトリかどうか         |

## ライセンス

[MIT](LICENSE)
