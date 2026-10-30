# notification-tools.nvim

轻量、无外部依赖的 Neovim 通知与任务状态插件，要求 Neovim **0.10+**。

- 右上角：有留白和级别色条的通知，标题/正文/附加信息分别高亮，重复内容合并计数。
- 右下角：紧凑的任务面板，按来源分组、右对齐百分比或耗时，长消息单独成行。
- 通用任务 API：由调用方管理自己的事件和任务句柄，插件不监听其他业务插件的事件。
- 可选 LSP work-done progress 接入，区分客户端和 token 类型，不替换 LSP handler。
- 通知历史、中文与多行文本、自适应宽度、小窗口布局、主题切换和安全卸载。
- 通知正文和附加信息支持常用行内 Markdown，按显示文字计算换行和宽度。

## 安装

lazy.nvim 配置可直接参考 [examples/lazy.lua](examples/lazy.lua)：

```lua
{
  "Jacky-Lzx/notification-tools.nvim",
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

## 历史筛选与阅读

`:Notifications` 打开历史，最新创建或更新的消息显示在顶部；也支持 `:Notifications level=warn source=lua_ls`。
窗口内仍可用原生 `/` 搜索、`y` 复制原始 Markdown，光标行显示原文，其他行 conceal。

| 按键 | 功能 |
| --- | --- |
| `]n` / `[n` | 下一条 / 上一条通知 |
| `gl` | 按最低等级筛选 |
| `gs` | 按来源精确筛选 |
| `gt` | 按标题子串筛选（不区分大小写） |
| `r` | 读取最新历史，按通知 ID 保留光标和阅读位置 |
| `R` | 清除所有筛选条件并刷新 |
| `<CR>` | 阅读选中的完整通知 / 任务结果 |
| `q` / `<Esc>` | 关闭 |

筛选条件显示在窗口标题中。刷新使用原窗口和缓冲区，不会在新通知到来时自动打断阅读。

```lua
local tools = require("notification-tools")
local errors = tools.history({ level = "error" }) -- 独立快照，不改变完整历史
tools.show_history({ level = "warn", source = "compiler", title = "Build" })
```

等级、来源和标题条件取交集；来源默认使用通知标题。标题或来源包含空格时建议使用 Lua API。

## 阅读长通知

`:NotificationsLatest` 打开最近创建或更新的普通通知；也可以在历史中按 `<CR>` 阅读选中条目，包括任务结果。
阅读窗口显示完整正文和附加信息，保留颜色和光标行 Markdown 展开，`r` 刷新内容，`q` / `<Esc>` 关闭。

```lua
local tools = require("notification-tools")
tools.show_notification()   -- 最新普通通知；返回 ID，找不到时返回 nil
tools.show_notification(id) -- 指定活动通知或历史记录（包括任务结果）的 ID
```

阅读活动通知期间暂停剩余超时，关闭窗口后继续剩余时间，不会重新获得一个完整超时周期。
阅读期间替换/合并通知会更新内容并重置剩余时间；按 `r` 查看最新版本。
固定通知仍然固定；已过期或被关闭的通知只从历史读取，不会重新弹出。
同一时间只打开一个历史/阅读窗口，切换窗口、手动关窗、删除缓冲区或重新 setup 都会清理阅读状态。
`history_size = 0` 时仍可阅读尚未被移除的活动通知。

## 免打扰与过滤

`:NotificationsDnd [on|off|toggle]` 切换免打扰（不带参数时切换）。
默认只允许 ERROR 弹出，其他通知仍记录到历史；任务面板不受影响。
开启时也会收起已有的低等级弹窗，关闭后不会补弹旧消息。

```lua
local tools = require("notification-tools")
tools.setup({
  notification = {
    dnd = false,
    dnd_level = "error", -- "off"：免打扰时所有等级都不弹出
    filter = function(notice)
      if notice.source == "noisy-plugin" then return "drop" end
      if notice.source == "background-build" then return "history" end
      return "show" -- nil 也表示正常显示；仍受免打扰限制
    end,
  },
})
tools.set_dnd(true)
local enabled = tools.is_dnd()
tools.toggle_dnd()
tools.notify("Built", "info", { source = "background-build", title = "Build" })
```

`source` 默认使用通知标题，显式替换时继承原来源；不同来源的通知不会自动合并。
过滤器收到独立的规范化字段表（message/level/title/source/details/timeout 等）；
`"history"` 仅记录，`"drop"` 忽略并返回 nil。最低等级 `level` 在过滤器之前生效。
过滤器须同步返回；抛错或返回非法值会报告错误并按 `"show"` 处理，不调用 `vim.notify` 递归报错。

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
`opts` 支持 `id`、`replace`（ID 或 `{ id = ... }`）、`title`、`icon`、`details`、`markdown` 和 `timeout`。
相同 ID 更新通知，并在历史中保留最新版本；表类型消息使用 `vim.inspect`。
`timeout` 从调用时开始计时，超出屏幕显示数量的通知仍会记录到历史中。

不传 `id/replace` 时，相同来源、标题、正文、附加信息、级别、图标和超时设置的活动通知会合并为一条，返回相同 ID，显示 `×N` 并重置消失时间。历史保留一条带 `count` 的最新记录。
显式 ID 始终独立；显式更新不会增加计数，内容改变时计数归一。
设置 `notification.merge_duplicates = false` 可关闭自动合并。

`tools.history()` 返回按时间从旧到新排列的独立快照；`tools.clear_history()` 清空历史。
历史只保存在当前会话内；任务默认仅记录失败和超时，可按下方策略调整。

### 行内 Markdown

```lua
vim.notify("Enabled **Inlay Hints**", vim.log.levels.INFO, { title = "Inlay Hints" })
-- 单条关闭：日志或代码需要原样显示时使用。
vim.notify("literal **stars**", nil, { markdown = false })
```

默认支持 `**粗体**` / `__粗体__`、`*斜体*` / `_斜体_`、行内代码、`~~删除线~~` 和 `[链接文字](url)`。
链接显示文字并加高亮，完整地址可在历史中查看。反斜杠可转义标点，行内代码中的星号等字符会原样显示。
格式范围限于单个逻辑行；窗口自动折行时样式会延续。标题、列表、表格、HTML 等块级布局不作特殊渲染，围栏代码块保留原文。这是轻量的行内显示支持，并非完整 Markdown 文档渲染器。

原始消息和 `details` 始终保留在 `history()` / 历史缓冲区中；去重也使用原文。通知标题和任务面板继续按纯文本显示。
`:Notifications` 对时间、级别、标题和正文分别高亮。普通模式下，光标所在行显示 Markdown 原文，其他行 conceal；移动光标后，原来的行会重新隐藏标记。复制仍得到原始 Markdown。conceal 设置仅作用于历史窗口，单条 `markdown = false` 的内容会保持原样。
设置 `notification.markdown = false` 可全局关闭；单条 `opts.markdown` 优先，并在同 ID 更新时继承。不同 Markdown 模式的通知不会自动合并。

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
- `handle:update(opts)` 可更新 `title/source/message/percentage/history`；省略字段保持原值。
- `handle:finish(message?, status?)` 的状态为 `success`（默认）、`error` 或 `cancelled`。
- `handle:cancel(message?)` 结束显示状态；实际取消工作由调用方负责。
- `handle:is_active()` 判断任务是否仍可更新。相同活动 ID 返回同一句柄；已结束的 ID 可重用。
- 方法支持链式调用。任务结束、清空、被容量淘汰、重新 setup 或 teardown 后，旧句柄调用不会生效。
- `tools.tasks()` 返回按创建时间从新到旧排列的任务快照；`tools.clear_tasks()` 清空任务。
- 在主循环中 `setup()` 后，通知和任务 API 可从 libuv 回调调用；浮窗操作会调度到主循环，不抢占编辑焦点。

默认 120 秒无更新的任务会标记超时，结束结果保留 1.5 秒。
长时间静默任务可设置 `progress.stale_timeout = 0`，并由生产者保证结束。
`max_pending` 分别限制活动通知和任务记录数，超过时淘汰最旧记录；默认各 100 条。

### 任务结果回溯

`progress.history = "errors"`（默认）将失败和无更新超时的任务写入通知历史；
`false` 关闭记录，`"all"` 同时保留成功和取消。单个任务可通过
`progress({ history = false })` 或 `handle:update({ history = "all" })` 覆盖全局策略。

结果记录包含标题、来源、最终消息、状态和耗时，任务面板消失后仍可通过 `:Notifications` 查看、筛选。
每次运行有独立的历史记录 ID，`task_id` 保存生产者的原 ID，复用任务 ID 不会覆盖旧结果。
`history()` 中此类记录的 `kind = "task"`，并包含 `status` 和 `duration`（毫秒）；普通通知的 `kind = "notification"`。
成功映射 INFO、失败映射 ERROR、取消映射 WARN；任务文本按纯文本显示。

结果只写历史，不额外弹窗；使用任务自己的记录策略，不经过普通通知的过滤器、最低等级或免打扰。
任务结果与普通通知共享 `history_size` 容量；`history_size = 0` 关闭全部历史。
清空任务和旧句柄的迟到回调不会产生结果记录。

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
    dnd = false,
    dnd_level = "error",
    -- filter = function(notice) return "show" end,
    markdown = true,
    merge_duplicates = true,
    timestamp = true, -- 标题右侧显示时间；重复时显示 ×N
    fade_out = 180, -- 在现有 timeout 的最后 180ms 淡出；0 关闭
    window = {
      padding = { horizontal = 2, vertical = 0 },
    },
  },
  progress = {
    enabled = true, -- 仅控制显示，任务 API 仍可使用
    max_items = 6,
    done_ttl = 1500,
    history = "errors", -- false：不记录；"all"：成功/失败/取消均记录
    stale_timeout = 120000,
    interval = 80,
    group_by_source = true,
    show_elapsed = true, -- 没有 percentage 时显示耗时
    fade_out = 240, -- 在 done_ttl 的最后 240ms 淡出；0 关闭
    window = {
      border = "rounded",
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

`window` 是公共样式默认值，`notification.window` 与 `progress.window` 分别覆盖它；原有公共配置仍然可用。默认通知和任务面板均使用圆角边框，通知内部不留上下空行。
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

- `:Notifications`：带颜色和 Markdown conceal 的历史浮窗，光标行自动展开原文，`q` / `<Esc>` 关闭。
- `:NotificationsDismiss`：关闭普通通知。
- `:NotificationsClear`：清空历史。
- `:NotificationsDnd [on|off|toggle]`：免打扰；不带参数时切换。
- `:NotificationsLatest`：阅读最新普通通知，暂停活动通知的剩余超时。
- `:NotificationToolsDemo`：预览通知和进度。

高亮组：`NotificationToolsNormal`、`NotificationToolsNotificationNormal`、`NotificationToolsProgressNormal`、
`NotificationToolsBorder`、`NotificationToolsTitle`、`NotificationToolsBody`、`NotificationToolsTaskTitle`、
`NotificationToolsMeta`、`NotificationToolsSource`、`NotificationToolsERROR/WARN/INFO/DEBUG/TRACE`、
`NotificationToolsProgress`、`NotificationToolsDone`、`NotificationToolsCancelled`。
行内代码和链接使用 `NotificationToolsMarkdownCode`、`NotificationToolsMarkdownLink`；粗体、斜体和删除线组合继承相应正文/附加信息的主题颜色。
默认链接到主题的 `NormalFloat/FloatBorder/Diagnostic*` 等高亮；使用 `nvim_set_hl` 可覆盖，切换主题后重新设置默认链接。

## 验证

```sh
sh tests/run.sh
```

需要 `nvim` 和 `stylua`。测试隔离 Neovim 的 state/cache/data 目录，覆盖通知更新和过滤、历史边界、任务生命周期、fast-event、卸载、LSP token、分屏 detach、小窗口和 Unicode 布局，以及重复计数、片段高亮、来源分组、窗口复用和独立淡出。新增覆盖免打扰无补弹、过滤路由、历史筛选与锚定刷新、任务结果保留，以及阅读期间暂停/恢复超时和外部关窗清理。

可选测试配置侧 Noice 适配器（使用本机已有 checkout）：

```sh
NOTIFICATION_TOOLS_NOICE_ROOT=/path/to/noice.nvim \
NOTIFICATION_TOOLS_NUI_ROOT=/path/to/nui.nvim sh tests/run.sh
```

设置 `NOTIFICATION_TOOLS_LAZY_ROOT=/path/to/lazy.nvim` 可同时验证本地 lazy.nvim 安装示例。

真实 TUI 验证脚本为 `tests/tui.lua`，运行方式：`nvim -n -u tests/tui.lua -i NONE`。
它自动检查浮窗位置、屏幕文本、Insert 模式编辑和窗口复用，结果写入 `$NOTIFICATION_TOOLS_TUI_RESULT`（默认 `/private/tmp/notification-tools-tui.json`），检查结束后保留预览。
可设置 `NOTIFICATION_TOOLS_THEME_ROOT=/path/to/catppuccin` 验证 Catppuccin Mocha 配色；设置 `NOTIFICATION_TOOLS_TUI_EXIT=1` 在验证后自动退出。
`nvim -n -u tests/history_tui.lua -i NONE` 单独验证历史窗口的颜色、光标行展开和窗口选项恢复。
`nvim -n -u tests/reading_tui.lua -i NONE` 验证完整内容阅读、暂停/恢复计时、原生筛选菜单及从历史回车阅读。两者使用同一组环境变量。
