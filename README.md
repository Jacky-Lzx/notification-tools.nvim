# notification-tools.nvim

轻量、无外部依赖的 Neovim 通知与任务状态插件，要求 Neovim **0.10+**。

- 右上角：有留白和级别色条的通知，标题/正文/附加信息分别高亮，重复内容合并计数。
- 右下角：紧凑的任务面板，按来源分组、右对齐百分比或耗时，长消息单独成行。
- 通用任务 API：由调用方管理自己的事件和任务句柄，插件不监听其他业务插件的事件。
- 可选 LSP work-done progress 接入，区分客户端和 token 类型，不替换 LSP handler。
- 通知历史、中文与多行文本、自适应宽度、小窗口布局、主题切换和安全卸载。

## 安装

当前为本地插件。lazy.nvim 配置可直接参考 [examples/lazy.lua](examples/lazy.lua)：

```lua
{
  dir = vim.fn.expand("~/Documents/Github/nvim_plugins/notification-tools.nvim"),
  name = "notification-tools.nvim",
  main = "notification-tools",
  lazy = false,
  priority = 1100,
  opts = {},
}
```

不使用 lazy.nvim 时，把目录加入 `runtimepath`，然后执行：

```lua
require("notification-tools").setup()
```

`:NotificationToolsDemo` 预览两个区域，`:checkhealth notification-tools` 检查环境。
仅 `require()` 不会接管通知；第一次调用 API 会使用默认配置初始化，建议先显式 `setup()`。

## 通知 API

```lua
local tools = require("notification-tools")

-- setup() 默认接管 vim.notify；两种写法都支持。
vim.notify("PDF 已生成", vim.log.levels.INFO, { title = "texquill" })
local id = tools.notify("正在连接…", "info", {
  title = "Connection",
  details = "api.example.com", -- 可选，次要信息使用较弱的高亮
  timeout = 0, -- 固定显示；其他非负数为毫秒
})
tools.notify("已连接", "info", { id = id, title = "Connection", timeout = 1500 })
tools.dismiss(id)
tools.dismiss() -- 关闭所有普通通知，保留任务和历史
```

`notify(message, level?, opts?)` 返回字符串/数字 ID；被级别过滤时返回 `nil`。
级别接受 `vim.log.levels` 数值或不区分大小写的 `trace/debug/info/warn/error/off`。
`opts` 支持 `id`、`replace`（ID 或 `{ id = ... }`）、`title`、`icon`、`details` 和 `timeout`。
相同 ID 更新通知，并在历史中保留最新版本；表类型消息使用 `vim.inspect`。
`timeout` 从调用时开始计时，超出屏幕显示数量的通知仍会记录到历史中。

不传 `id/replace` 时，相同标题、正文、附加信息、级别、图标和超时设置的活动通知会合并为一条，返回相同 ID，显示 `×N` 并重置消失时间。历史保留一条带 `count` 的最新记录。
显式 ID 始终独立；显式更新不会增加计数，内容改变时计数归一。
设置 `notification.merge_duplicates = false` 可关闭自动合并。

`tools.history()` 返回按时间从旧到新排列的独立快照；`tools.clear_history()` 清空历史。
历史只保存在当前会话内，任务结果不写入通知历史。

## 其他插件接入任务 API

由调用方在任务开始时创建句柄，在自己的进度、完成或取消回调中更新句柄。
无需注册插件专属配置或依赖其事件名。完整例子见 [examples/task.lua](examples/task.lua)。

```lua
local task = require("notification-tools").progress({
  id = "my-plugin:build:1", -- 可省略以自动生成；建议给自定义 ID 加命名空间
  title = "Building document",
  source = "my-plugin",
  message = "Starting…",
  percentage = 0, -- 可省略；数字会限制到 0–100
})

task:update({ percentage = 65, message = "Compiling references" })
task:finish("PDF ready")
-- 或 task:finish("Compiler failed", "error")
-- 或 task:cancel("Stopped by user")
```

- `progress(opts)` 返回 `{ id, update, finish, cancel, is_active }` 句柄。
- `handle:update(opts)` 可更新 `title/source/message/percentage`；省略字段保持原值。
- `handle:finish(message?, status?)` 的状态为 `success`（默认）、`error` 或 `cancelled`。
- `handle:cancel(message?)` 结束显示状态；实际取消工作由调用方负责。
- `handle:is_active()` 判断任务是否仍可更新。相同活动 ID 返回同一句柄；已结束的 ID 可重用。
- 方法支持链式调用。任务结束、清空、被容量淘汰、重新 setup 或 teardown 后，旧句柄调用不会生效。
- `tools.tasks()` 返回按创建时间从新到旧排列的任务快照；`tools.clear_tasks()` 清空任务。
- 在主循环中 `setup()` 后，通知和任务 API 可从 libuv 回调调用；浮窗操作会调度到主循环，不抢占编辑焦点。

默认 120 秒无更新的任务会标记超时，结束结果保留 1.5 秒。
长时间静默任务可设置 `progress.stale_timeout = 0`，并由生产者保证结束。
`max_pending` 分别限制活动通知和任务记录数，超过时淘汰最旧记录；默认各 100 条。

## 参考现有 Neovim 配置迁移

当前配置中 Fidget 处理 LSP/其他任务，Snacks notifier 处理通知，Noice 处理命令行和消息。
本仓库不修改你的 `~/.config/nvim`。迁移时：

1. 添加本插件的 lazy.nvim spec，加载时机早于通知生产者。
2. 禁用 `plugins/ui/fidget.lua`，并删除 `nvim-lspconfig.lua` 和其他插件依赖中的 Fidget。
3. 业务侧原有 Fidget hooks 改用上面的任务 API，由业务配置继续管理事件。
4. 在 `plugins/navigation/snacks.lua` 中设置 `notifier.enabled = false`。
5. 将原 `<leader>sn`、`<leader>n` 改为 `:Notifications`，`<leader>un` 改为 `:NotificationsDismiss`；移除原 Snacks 同名映射，避免重复定义。
6. 保留 Noice 的 `notify.enabled = false` 和 `lsp.progress.enabled = false`。

Noice 的 `notify` view 默认直接调用 Snacks/nvim-notify，关闭 Snacks 后还需要指定后端。
提供一个**配置侧**适配器 [examples/noice.lua](examples/noice.lua)：将它复制到
`~/.config/nvim/lua/integrations/notification_tools_noice.lua`，在现有 Noice opts 中添加：

```lua
views = require("integrations.notification_tools_noice"),
```

这样 Noice 的 LSP 消息、警告等通过公开 `notify` API 进入右上角，原有命令行和消息路由继续由 Noice 管理。
适配器由用户配置加载；插件核心不依赖 Noice/NUI，也不会修改它们的配置。

## 配置

下面列出常用选项，完整默认值见 [config.lua](lua/notification-tools/config.lua)。

```lua
require("notification-tools").setup({
  notify = true, -- false：只通过 tools.notify() 显示通知，不接管 vim.notify
  level = vim.log.levels.INFO,
  timeout = 4000,
  history_size = 200, -- 0：关闭历史
  max_notifications = 5,
  max_pending = 100,
  window = {
    border = "rounded", -- rounded/single/double/solid/none 或 ""
    winblend = 0,
    min_width = 24,
    max_width = 60,
    max_height = 8, -- 每条通知的正文最大行数，完整内容仍在历史中
    top = 1, right = 1, bottom = 1,
    zindex = 150,
    gap = 1,
  },
  notification = {
    merge_duplicates = true,
    timestamp = true, -- 标题右侧显示时间；重复时显示 ×N
    fade_out = 180, -- 在现有 timeout 的最后 180ms 淡出；0 关闭
    window = {
      padding = { horizontal = 2, vertical = 1 },
    },
  },
  progress = {
    enabled = true, -- 仅控制显示，任务 API 仍可使用
    max_items = 6,
    done_ttl = 1500,
    stale_timeout = 120000,
    interval = 80,
    group_by_source = true,
    show_elapsed = true, -- 没有 percentage 时显示耗时
    fade_out = 240, -- 在 done_ttl 的最后 240ms 淡出；0 关闭
    window = {
      border = "none",
      min_width = 24,
      max_width = 44,
      max_height = 12, -- 面板总内容行数，包含来源、消息和溢出提示
      padding = { horizontal = 1, vertical = 0 },
    },
    avoid = { "NvimTree", "TestExplorer" }, -- 当前窗口为这些 filetype 时隐藏任务
    spinner = { "⠋", "⠙", "⠹", "⠸", "⠼", "⠴", "⠦", "⠧", "⠇", "⠏" },
  },
  lsp = { enabled = true, ignore = {} }, -- ignore 中填写客户端名
})
```

`window` 是公共样式默认值，`notification.window` 与 `progress.window` 分别覆盖它；原有公共配置仍然可用。默认通知保留圆角边框，任务面板无边框。
两种窗口可分别设置边框、宽度、透明度、留白和边距。`padding` 单位是字符单元/行。通知的 `max_height` 限制正文和附加信息总行数；任务的 `max_height` 限制面板总行数。

通知与任务同时存在时，任务最多占用下半部分，通知使用余下空间。小窗口中先省略任务的空行、附加消息和来源标题，再限制可见任务数；记录仍可通过历史或任务 API 获取。
通知按创建顺序向下叠放，更新不会改变所在顺序；放不下时优先保留较新的通知。任务按来源首次出现的顺序分组，组内保持创建顺序。`progress.max_items` 限制任务数。
窗口宽度按内容测量，同一浮窗存在期间只扩不缩，屏幕变小时仍会收缩；浮窗关闭后重新测量，减少更新时的跳动。

完成/失败/取消任务在保留时间末尾独立淡出，同组的活动任务保持正常。淡出不会延长 `timeout/done_ttl`，固定通知不会淡出；真实颜色过渡取决于终端的 true-color 支持。
LSP 采用 Neovim 的 `LspProgress` 事件；非 work-done 的 partial results 不显示。
中途加载时会从后续 report 创建任务，但不会读取和消耗客户端的历史进度队列。

`setup()` 可重复调用，会清理旧状态。`tools.teardown()` 关闭窗口、定时器和自动命令；仅在仍由本插件持有 `vim.notify` 时恢复前一个函数。
没有活动记录时不保留刷新定时器。定时器用于刷新任务动画和清理超时记录。

## 命令和主题

- `:Notifications`：可滚动、自动换行的历史浮窗，`q` / `<Esc>` 关闭。
- `:NotificationsDismiss`：关闭普通通知。
- `:NotificationsClear`：清空历史。
- `:NotificationToolsDemo`：预览通知和进度。

高亮组：`NotificationToolsNormal`、`NotificationToolsNotificationNormal`、`NotificationToolsProgressNormal`、
`NotificationToolsBorder`、`NotificationToolsTitle`、`NotificationToolsBody`、`NotificationToolsTaskTitle`、
`NotificationToolsMeta`、`NotificationToolsSource`、`NotificationToolsERROR/WARN/INFO/DEBUG/TRACE`、
`NotificationToolsProgress`、`NotificationToolsDone`、`NotificationToolsCancelled`。
默认链接到主题的 `NormalFloat/FloatBorder/Diagnostic*` 等高亮；使用 `nvim_set_hl` 可覆盖，切换主题后重新设置默认链接。

## 验证

```sh
sh tests/run.sh
```

需要 `nvim` 和 `stylua`。测试隔离 Neovim 的 state/cache/data 目录，覆盖通知更新和过滤、历史边界、任务生命周期、fast-event、卸载、LSP token、分屏 detach、小窗口和 Unicode 布局，以及重复计数、片段高亮、来源分组、窗口复用和独立淡出。

可选测试配置侧 Noice 适配器（使用本机已有 checkout）：

```sh
NOTIFICATION_TOOLS_NOICE_ROOT=/path/to/noice.nvim \
NOTIFICATION_TOOLS_NUI_ROOT=/path/to/nui.nvim sh tests/run.sh
```

设置 `NOTIFICATION_TOOLS_LAZY_ROOT=/path/to/lazy.nvim` 可同时验证本地 lazy.nvim 安装示例。

真实 TUI 验证脚本为 `tests/tui.lua`，运行方式：`nvim -n -u tests/tui.lua -i NONE`。
它自动检查浮窗位置、屏幕文本、Insert 模式编辑和窗口复用，结果写入 `$NOTIFICATION_TOOLS_TUI_RESULT`（默认 `/private/tmp/notification-tools-tui.json`），检查结束后保留预览。
可设置 `NOTIFICATION_TOOLS_THEME_ROOT=/path/to/catppuccin` 验证 Catppuccin Mocha 配色；设置 `NOTIFICATION_TOOLS_TUI_EXIT=1` 在验证后自动退出。
