-- Deterministic documentation scenes rendered by the real plugin and Neovim UI.
vim.opt.runtimepath:prepend(vim.fn.getcwd())
vim.o.termguicolors = true
vim.o.swapfile = false
vim.o.number = true
vim.o.signcolumn = "no"
vim.o.laststatus = 3
vim.o.showtabline = 0
vim.o.cmdheight = 0
vim.o.ruler = false
vim.o.showmode = false
vim.o.fillchars = "eob: "
local theme = vim.env.NOTIFICATION_TOOLS_THEME_ROOT
if theme and theme ~= "" then
  vim.opt.runtimepath:append(theme)
  require("catppuccin").setup({ flavour = "mocha" })
  vim.cmd.colorscheme("catppuccin")
else
  vim.cmd.colorscheme("habamax")
end
vim.cmd("syntax on")
vim.api.nvim_set_hl(0, "ScreenshotMode", { fg = "#1e1e2e", bg = "#89b4fa", bold = true })
vim.api.nvim_set_hl(0, "ScreenshotStatus", { fg = "#a6adc8", bg = "#181825" })
vim.o.statusline =
  "%#ScreenshotMode# NORMAL %#ScreenshotStatus#  notification-demo.lua %=Lua  UTF-8   %#ScreenshotMode# 12:34 "
vim.api.nvim_buf_set_name(0, "notification-demo.lua")
vim.api.nvim_buf_set_lines(0, 0, -1, false, {
  "-- Keep the editor focused. Let the work stay visible.",
  "",
  'local tools = require("notification-tools")',
  "",
  "tools.setup({",
  '  window = { border = "rounded" },',
  '  progress = { history = "errors" },',
  "})",
  "",
  "-- One handle for the whole job.",
  "local task = tools.progress({",
  '  title = "Generating preview",',
  '  source = "Build",',
  '  message = "Rendering pages",',
  "})",
  "",
  "task:update({ percentage = 65 })",
  'task:finish("Preview ready")',
  "",
  "-- Notifications work with the API you already use.",
  'vim.notify("Document compiled", vim.log.levels.INFO, {',
  '  title = "Build",',
  '  details = "main.pdf · 12 pages",',
  "})",
})
vim.bo.filetype = "lua"
vim.api.nvim_win_set_cursor(0, { 11, 0 })
local clock = 1000
require("notification-tools.state").now = function()
  return clock
end
-- Freeze timestamps as well as animation/elapsed time for repeatable assets.
local real_time = os.time
local fixed_time = real_time({ year = 2026, month = 10, day = 30, hour = 12, min = 34, sec = 0 })
os.time = function(date)
  return date and real_time(date) or fixed_time
end
local tools = require("notification-tools")
tools.setup({ timeout = 0, progress = { stale_timeout = 0 } })
-- Public highlight overrides: this palette is part of the screenshot fixture.
for name, definition in pairs({
  Border = { fg = "#89b4fa", bg = "#181825" },
  Body = { fg = "#cdd6f4" },
  TaskTitle = { fg = "#cdd6f4" },
  Meta = { fg = "#a6adc8" },
  Source = { fg = "#a6adc8", italic = true },
  INFO = { fg = "#89dceb" },
  WARN = { fg = "#f9e2af" },
  ERROR = { fg = "#f38ba8" },
}) do
  vim.api.nvim_set_hl(0, "NotificationTools" .. name, definition)
end
local scene = vim.g.notification_screenshot_scene or "overview"
if scene == "overview" then
  tools.notify("Document compiled", "info", { title = "Build", details = "main.pdf · 12 pages" })
  tools.notify("Document compiled", "info", { title = "Build", details = "main.pdf · 12 pages" })
  tools.notify("Enabled **Inlay Hints**", "info", { title = "Editor" })
  tools.progress({
    title = "Indexing workspace",
    source = "lua_ls",
    percentage = 62,
    message = "Scanning project files",
  })
  tools.progress({ title = "Generating preview", source = "Build", message = "Rendering pages" })
  clock = 2400
else
  local build = tools.progress({ title = "Build", source = "compiler" })
  clock = 4200
  build:finish("Missing bibliography entry: smith2025", "error")
  tools.notify("Workspace library is incomplete", "warn", { title = "lua_ls" })
  for _ = 1, 2 do
    tools.notify("Document compiled", "info", { title = "Build", details = "main.pdf · 12 pages" })
  end
  tools.notify("Enabled **Inlay Hints** and _type annotations_", "info", {
    title = "Editor",
    details = "Read [the guide](https://neovim.io/doc/user/lsp.html)",
  })
  tools.dismiss()
  tools.clear_tasks()
  tools.show_history()
  if scene == "history-source" then
    vim.schedule(function()
      vim.api.nvim_win_set_cursor(0, { 2, 0 })
    end)
  end
end
