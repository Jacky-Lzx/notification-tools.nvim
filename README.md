# notification-tools.nvim

Notification history uses selection-tools time, level, title and content components. Time inherits `component_defaults.time` and remains searchable. Notification semantic colors use component-local highlights.

Readable notifications, grouped progress and searchable history.

![Neovim showing Markdown notifications at the top right and grouped LSP and build progress at the bottom right](.github/assets/overview.png)

## Features

- Read Markdown notices and inspect a persistent session history.
- Group producer-owned progress handles without owning their jobs.
- Route messages, reduce noise and pause expiry while reading.

## Requirements

Neovim **0.10+**. No runtime dependencies. Configure one owner for `vim.notify` and external message handling.

## Installation

With lazy.nvim:

```lua
{
  "Jacky-Lzx/notification-tools.nvim",
  main = "notification-tools",
  opts = {},
}
```

Or put this repository and its required dependencies on `runtimepath`, then call:

```lua
require("notification-tools").setup({})
```

## Usage

```vim
:Notifications
:NotificationsDismiss
:NotificationToolsInfo
```

## Documentation

- [Screenshot scene](scripts/screenshot-scene.lua).
- [Complete reference](doc/notification-tools.txt) — `:help notification-tools`.
- [Workflow and integration guide](doc/guide.md).
- [More screenshots](doc/gallery.md).
- Diagnose availability with `:checkhealth notification-tools`.

## Development

Run from the repository root:

```sh
python3 tests/run.py unit --filter docs
python3 tests/run.py default
```

See [the test workflow](tests/README.md) for dependencies, optional suites and
retained failure evidence. Local development overrides belong in your package
manager configuration; public installation uses the repository above.

[License](LICENSE).
