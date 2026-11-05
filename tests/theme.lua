local h = dofile("tests/helpers.lua")
local tools = require("notification-tools")
local api = vim.api
vim.o.columns, vim.o.lines = 120, 50

local function foreground(name)
  return require("notification-tools.theme").definition(name).fg
end
local function settle()
  vim.wait(60, function()
    return false
  end, 5)
end
local function standards(fg, bg)
  api.nvim_set_hl(0, "Normal", { fg = fg, bg = bg })
  api.nvim_set_hl(0, "NormalFloat", { fg = fg, bg = bg, italic = true })
end
local function show()
  tools.notify("**Theme body**", "warn", { title = "Build" })
  tools.progress({ title = "Theme task", percentage = 50 })
  h.wait(function()
    return #h.floats() == 2
  end)
end

-- Schemes need not clear plugin highlights. A copied dark fg must still refresh.
standards(0xf8f8f2, 0x282a36)
tools.setup({ notify = false, timeout = 0, progress = { stale_timeout = 0 } })
show()
h.eq(0xf8f8f2, foreground("NotificationToolsBody"))
for _, colors in ipairs({ { 0x4c4f69, 0xe6e9ef }, { 0xf8f8f2, 0x282a36 } }) do
  standards(0x010203, colors[2])
  api.nvim_exec_autocmds("ColorScheme", { pattern = "no-clear" })
  -- The plugin must wait until the theme's synchronous overrides are complete.
  api.nvim_set_hl(0, "NormalFloat", { fg = colors[1], bg = colors[2], italic = true })
  h.wait(function()
    return foreground("NotificationToolsBodyMarkdownBold") == colors[1]
  end)
  h.eq(colors[1], foreground("NotificationToolsTaskTitle"))
  local body = api.nvim_get_hl(0, { name = "NotificationToolsBody", link = false })
  h.eq(nil, body.bg)
  h.eq(nil, body.italic)
end
assert(not package.loaded.theme_tools, "standalone rendering must not load theme-tools")

-- Explicit overrides survive refresh, including links and per-surface colors.
api.nvim_set_hl(0, "NotificationToolsBody", { fg = 0x123456 })
api.nvim_set_hl(0, "NotificationToolsSource", { link = "Title" })
api.nvim_set_hl(0, "NotificationToolsProgressNormal", { fg = 0xabcdef, bg = 0x102030 })
standards(0x4c4f69, 0xe6e9ef)
api.nvim_exec_autocmds("ColorScheme", { pattern = "no-clear" })
settle()
h.eq(0x123456, foreground("NotificationToolsBody"))
h.eq("Title", api.nvim_get_hl(0, { name = "NotificationToolsSource", link = true }).link)
h.eq(0x102030, api.nvim_get_hl(0, { name = "NotificationToolsProgressNormal" }).bg)
tools.teardown()
vim.cmd("highlight clear")

-- Attach after first display through ThemeToolsReady; use semantic overrides,
-- even when the standard theme groups have different colors.
local callbacks, attached, detached = {}, 0, 0
local current = {
  ui = {
    float_fg = "#223344",
    float_bg = "#ddeeff",
    border = "#334455",
    accent = "#445566",
    muted = "#556677",
  },
  diagnostic = {
    error = "#aa1122",
    warn = "#bb2233",
    info = "#cc3344",
    ok = "#117733",
  },
  palette = { green = "#228844" },
}
local function publish()
  for _, callback in pairs(callbacks) do
    callback(vim.deepcopy(current))
  end
end
tools.setup({ notify = false, timeout = 0, progress = { stale_timeout = 0 } })
show()
package.loaded.theme_tools = {
  on_change = function(id, callback)
    attached = attached + 1
    callbacks[id] = callback
    callback(vim.deepcopy(current))
    return function()
      detached = detached + 1
      if callbacks[id] == callback then
        callbacks[id] = nil
      end
    end
  end,
}
api.nvim_exec_autocmds("User", { pattern = "ThemeToolsReady" })
h.wait(function()
  return foreground("NotificationToolsBodyMarkdownBold") == 0x223344
end)
h.eq(1, attached)
h.eq(0x223344, foreground("NotificationToolsTaskTitle"))
h.eq(0xddeeff, require("notification-tools.theme").definition("NotificationToolsNormal").bg)
h.eq(0x334455, foreground("NotificationToolsBorder"))
h.eq(0x445566, foreground("NotificationToolsTitle"))
h.eq(0x556677, foreground("NotificationToolsMeta"))
h.eq(0xbb2233, foreground("NotificationToolsWARN"))
h.eq(0x117733, foreground("NotificationToolsDone"))

-- Restoring a preview snapshot must not turn old defaults into fixed overrides.
local snapshot = {}
for name, value in pairs(api.nvim_get_hl(0, {})) do
  if name:find("^NotificationTools") then
    snapshot[name] = value
  end
end
current.ui.float_fg = "#778899"
publish()
for name, value in pairs(snapshot) do
  api.nvim_set_hl(0, name, value)
end
current.ui.float_fg = "#223344"
publish()
current.ui.float_fg = "#334455"
publish()
h.eq(0x334455, foreground("NotificationToolsBody"))
current.ui.float_fg = "#223344"
publish()

tools.show_history()
h.wait(function()
  return vim.bo.filetype == "notification-tools-history"
end)
local history = api.nvim_get_current_buf()
h.eq("notification-tools-history", vim.bo[history].filetype)
-- A window-local remapping must never become a global default or Markdown fg.
api.nvim_set_hl(0, "OtherWindowText", { fg = 0xff0000 })
vim.wo.winhighlight = "Normal:OtherWindowText,NotificationToolsBody:OtherWindowText"
current.ui.float_fg, current.ui.float_bg = "#ddeeff", "NONE"
publish()
h.wait(function()
  return foreground("NotificationToolsBodyMarkdownBold") == 0xddeeff
end)
h.eq(0xddeeff, foreground("NotificationToolsTaskTitle"))
h.eq(nil, require("notification-tools.theme").definition("NotificationToolsNormal").bg)
assert(api.nvim_get_hl(0, { name = "NotificationToolsBodyMarkdownBold" }).bold)
assert(api.nvim_buf_is_valid(history))
local ns = api.nvim_create_namespace("notification-tools")
local has_bold = false
for _, mark in ipairs(api.nvim_buf_get_extmarks(history, ns, 0, -1, { details = true })) do
  has_bold = has_bold or mark[4].hl_group == "NotificationToolsBodyMarkdownBold"
end
assert(has_bold, "open history must retain its updated Markdown highlights")

api.nvim_set_hl(0, "NotificationToolsTaskTitle", { fg = 0x123456 })
current.ui.float_fg = "#334455"
publish()
h.eq(0x123456, foreground("NotificationToolsTaskTitle"))
h.eq(0x334455, foreground("NotificationToolsBody"))
api.nvim_exec_autocmds("ColorScheme", { pattern = "no-clear" })
api.nvim_exec_autocmds("User", { pattern = "ThemeToolsReady" })
h.eq(1, attached)
tools.teardown()
h.eq(1, detached)
h.eq(nil, next(callbacks))

-- Reconfiguration replaces its subscription; teardown stops subsequent updates.
tools.setup({ notify = false })
h.eq(2, attached)
tools.setup({ notify = false })
h.eq(3, attached)
h.eq(2, detached)
tools.teardown()
h.eq(3, detached)
local before = foreground("NotificationToolsBody")
current.ui.float_fg = "#ffffff"
publish()
h.eq(before, foreground("NotificationToolsBody"))
package.loaded.theme_tools = nil

print(
  "theme: dark/light refresh, shared palette, snapshot restoration, overrides, history, remapping and cleanup passed"
)
