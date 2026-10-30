---@meta

---Finite string/number IDs are shared by notifications, tasks and history records.
---@alias notification_tools.ID string|number
---Levels accept vim.log.levels integers and case-insensitive names.
---@alias notification_tools.Level integer|'trace'|'debug'|'info'|'warn'|'warning'|'error'|'off'|string
---@alias notification_tools.TaskStatus 'success'|'error'|'cancelled'
---@alias notification_tools.ProgressStyle 'bar'|'compact'
---@alias notification_tools.HistoryPolicy false|'errors'|'all'
---@alias notification_tools.Route 'show'|'history'|'drop'
---@alias notification_tools.Border 'rounded'|'single'|'double'|'solid'|'none'|''

---@class notification_tools.Padding
---@field horizontal? integer Horizontal padding in display cells.
---@field vertical? integer Vertical padding in lines.

---@class notification_tools.WindowConfig
---@field border? notification_tools.Border
---@field winblend? integer Transparency, 0..100.
---@field min_width? integer Preferred minimum width in display cells.
---@field max_width? integer Maximum width in display cells.
---@field max_height? integer Maximum content rows.
---@field top? integer Top margin in display cells.
---@field right? integer Right margin in display cells.
---@field bottom? integer Bottom margin in display cells.
---@field zindex? integer Float stacking priority.
---@field gap? integer Gap between windows in display cells.
---@field padding? notification_tools.Padding

---Normalized independent fields passed to the synchronous notification filter.
---@class notification_tools.FilterNotice
---@field id? notification_tools.ID Present when the caller supplied an ID/replace.
---@field message string
---@field level integer Numeric vim.log.levels value.
---@field title string
---@field source string
---@field details string
---@field icon? string
---@field markdown boolean
---@field timeout number Nonnegative milliseconds; 0 pins.

---@alias notification_tools.Filter fun(notice: notification_tools.FilterNotice): notification_tools.Route?

---@class notification_tools.NotificationConfig
---@field dnd? boolean
---@field dnd_level? notification_tools.Level Minimum popup severity during DND; off suppresses all.
---@field filter? notification_tools.Filter nil/show displays normally, history retains only, drop discards.
---@field markdown? boolean Enable inline Markdown in body/details.
---@field merge_duplicates? boolean
---@field timestamp? boolean
---@field fade_out? integer Fade duration within the existing timeout, in milliseconds.
---@field window? notification_tools.WindowConfig Overrides shared window settings.

---@class notification_tools.ProgressConfig
---@field enabled? boolean Disable only the panel, keeping the task API available.
---@field style? notification_tools.ProgressStyle Defaults to bar; compact uses spinner/text rows.
---@field max_items? integer Maximum displayed tasks.
---@field done_ttl? integer Result lifetime in milliseconds.
---@field history? notification_tools.HistoryPolicy Defaults to errors.
---@field stale_timeout? integer Milliseconds without updates before timeout; 0 disables.
---@field interval? integer Animation interval in milliseconds, at least 16.
---@field group_by_source? boolean
---@field show_elapsed? boolean Show elapsed time when percentage is absent.
---@field fade_out? integer Fade duration within done_ttl, in milliseconds.
---@field window? notification_tools.WindowConfig Overrides shared window settings.
---@field avoid? string[] Current-buffer filetypes that hide the panel.
---@field spinner? string[] Nonempty animation frames; lists replace defaults.

---@class notification_tools.LspConfig
---@field enabled? boolean Subscribe to work-done progress without replacing LSP handlers.
---@field ignore? string[] Client names to ignore.

---All setup fields are optional; nested tables override their defaults.
---@class notification_tools.Config
---@field notify? boolean Own vim.notify; false keeps only the explicit API.
---@field level? notification_tools.Level Minimum ordinary notification severity.
---@field timeout? integer Default lifetime in milliseconds; 0 pins.
---@field history_size? integer Maximum retained records; 0 disables history.
---@field max_notifications? integer Maximum visible notification windows.
---@field max_pending? integer Separate active-record limits for notices and tasks.
---@field window? notification_tools.WindowConfig
---@field notification? notification_tools.NotificationConfig
---@field progress? notification_tools.ProgressConfig
---@field lsp? notification_tools.LspConfig
---@field icons? table<string, string> Severity names (ERROR/WARN/INFO/DEBUG/TRACE) to icons.

---@class notification_tools.Replace
---@field id notification_tools.ID

---@class notification_tools.NotifyOptions
---@field id? notification_tools.ID
---@field replace? notification_tools.ID|notification_tools.Replace
---@field title? string
---@field source? string Defaults to title on creation; retained on replacement.
---@field icon? string
---@field details? string Secondary text, including inline Markdown.
---@field timeout? number Nonnegative milliseconds; 0 pins.
---@field markdown? boolean Override inline Markdown for this notice.

---@class notification_tools.HistoryFilters
---@field level? notification_tools.Level Minimum severity.
---@field source? string Exact source match.
---@field title? string Case-insensitive literal title substring.

---@class notification_tools.TaskUpdate
---@field title? string
---@field source? string
---@field message? string
---@field percentage? number Clamped to integer 0..100; omission retains the previous value.
---@field history? notification_tools.HistoryPolicy Override the result-recording policy.

---@class notification_tools.TaskOptions: notification_tools.TaskUpdate
---@field id? notification_tools.ID Optional namespaced producer ID.

---Methods return the handle and become inert after completion/eviction/teardown.
---Cancellation marks the display only; the caller cancels its actual job.
---@class notification_tools.TaskHandle
---@field id notification_tools.ID
---@field update fun(self: notification_tools.TaskHandle, update?: notification_tools.TaskUpdate): notification_tools.TaskHandle
---@field finish fun(self: notification_tools.TaskHandle, message?: string, status?: notification_tools.TaskStatus): notification_tools.TaskHandle
---@field cancel fun(self: notification_tools.TaskHandle, message?: string): notification_tools.TaskHandle
---@field is_active fun(self: notification_tools.TaskHandle): boolean

---Independent public snapshot; tasks() never exposes the internal handle.
---@class notification_tools.TaskSnapshot
---@field id notification_tools.ID
---@field title string
---@field source string
---@field message string
---@field history notification_tools.HistoryPolicy
---@field percentage? integer
---@field order integer Creation order.
---@field started number Monotonic milliseconds, not Unix time.
---@field updated number Monotonic milliseconds.
---@field done? boolean
---@field status? notification_tools.TaskStatus
---@field finished? number Monotonic milliseconds.
---@field expires? number Monotonic milliseconds.
---@field lifetime? integer Result lifetime in milliseconds.

---Independent history snapshots retain original Markdown and full message text.
---@class notification_tools.HistoryRecord
---@field id notification_tools.ID Record ID; task runs have independent record IDs.
---@field message string
---@field title string
---@field source string
---@field details string
---@field level integer Numeric vim.log.levels value.
---@field markdown boolean
---@field count integer Merged notification count.
---@field time integer Unix timestamp in seconds.
---@field order integer
---@field timeout number
---@field display boolean Whether the record was eligible for an ordinary popup.
---@field icon? string
---@field revision? integer Last ordinary-notification update order.
---@field content_revision? integer Parsed-content revision.
---@field expires? number Monotonic milliseconds at the time of archiving.
---@field paused? boolean
---@field remaining? number Paused timeout remainder in milliseconds.

---@class notification_tools.NotificationRecord: notification_tools.HistoryRecord
---@field kind 'notification'

---@class notification_tools.TaskResultRecord: notification_tools.HistoryRecord
---@field kind 'task'
---@field task_id notification_tools.ID Original producer task ID.
---@field status notification_tools.TaskStatus
---@field duration number Elapsed milliseconds.

---@alias notification_tools.Record notification_tools.NotificationRecord|notification_tools.TaskResultRecord
