-- Run from the repository root: nvim -n -u tests/tui.lua -i NONE
vim.opt.runtimepath:prepend(vim.fn.getcwd())
vim.o.termguicolors = true
vim.o.laststatus = 3
vim.o.showtabline = 2
vim.o.number = true
vim.o.swapfile = false
local theme = vim.env.NOTIFICATION_TOOLS_THEME_ROOT
if theme and theme ~= "" then
  vim.opt.runtimepath:append(theme)
  require("catppuccin").setup({
    flavour = "mocha",
    transparent_background = true,
    float = { transparent = true },
  })
  vim.cmd.colorscheme("catppuccin")
end
local tools = require("notification-tools")
tools.setup({ timeout = 0, progress = { stale_timeout = 0, done_ttl = 700, fade_out = 320 } })
vim.api.nvim_buf_set_lines(0, 0, -1, false, {
  "-- notification-tools.nvim: real TUI verification",
  "-- Top right: notifications. Bottom right: live task status.",
  "local project = 'workspace'",
  "",
})
vim.bo.filetype = "lua"
local original_buf, original_win = vim.api.nvim_get_current_buf(), vim.api.nvim_get_current_win()
local task, notice
local waiting_bar, waiting_changed
local snapshots = {}
local failed = false
local function screen()
  vim.cmd.redraw()
  local rows = {}
  for row = 1, vim.o.lines do
    local line = {}
    for col = 1, vim.o.columns do
      line[#line + 1] = vim.fn.screenstring(row, col)
    end
    rows[#rows + 1] = table.concat(line)
  end
  return table.concat(rows, "\n")
end
local function floats()
  local result = {}
  for _, win in ipairs(vim.api.nvim_list_wins()) do
    if vim.bo[vim.api.nvim_win_get_buf(win)].filetype == "notification-tools" then
      result[win] = vim.api.nvim_win_get_buf(win)
    end
  end
  return result
end
local function preview_bar()
  for _, buf in pairs(floats()) do
    local lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
    for index, line in ipairs(lines) do
      if line:find("Building document", 1, true) then
        return lines[index + 1]
      end
    end
  end
end
local function record_error(err)
  failed = true
  local result = { ok = false, error = tostring(err), screen = screen() }
  vim.fn.writefile(
    { vim.json.encode(result) },
    vim.env.NOTIFICATION_TOOLS_TUI_RESULT or "/private/tmp/notification-tools-tui.json"
  )
  if vim.env.NOTIFICATION_TOOLS_TUI_EXIT == "1" then
    vim.cmd("cquit 1")
  end
end
local function later(ms, callback)
  vim.defer_fn(function()
    local ok, err = xpcall(callback, debug.traceback)
    if not ok then
      record_error(err)
    end
  end, ms)
end
later(150, function()
  assert(#vim.api.nvim_list_uis() > 0, "A real TUI is required")
  notice = tools.notify(
    "Enabled **Inlay Hints**",
    "info",
    { title = "Inlay Hints", details = "Status: **enabled** · `main.pdf`" }
  )
  assert(
    notice
      == tools.notify(
        "Enabled **Inlay Hints**",
        "info",
        { title = "Inlay Hints", details = "Status: **enabled** · `main.pdf`" }
      )
  )
  tools.notify("One warning from the language server", "warn", { title = "LSP" })
  task = tools.progress({
    title = "Indexing",
    source = "lua_ls",
    percentage = 35,
    message = "Reading files",
  })
  tools.progress({
    title = "Building document",
    source = "texquill",
    message = "Compiling references",
  })
end)
local initial
later(400, function()
  initial = floats()
  assert(vim.tbl_count(initial) == 3, "Expected two notifications and a task panel")
  assert(vim.api.nvim_get_current_win() == original_win, "Floats took focus")
  local text = screen()
  assert(
    text:find("Indexing", 1, true) and text:find("35%", 1, true) and text:find("Build"),
    "Text was not painted"
  )
  assert(
    text:find("×2", 1, true) and text:find("main.pdf", 1, true),
    "Notification count/details were not painted"
  )
  assert(
    text:find("lua_ls", 1, true) and text:find("texquill", 1, true),
    "Source groups were not painted"
  )
  snapshots.before = text
  waiting_bar = assert(preview_bar())
  assert(
    waiting_bar:find("━", 1, true) and waiting_bar:find("─", 1, true),
    "Default progress bars must actually be painted"
  )
  assert(
    text:find("Enabled Inlay Hints", 1, true) and not text:find("**", 1, true),
    "Inline Markdown markers were painted"
  )
  local strong = false
  local markdown_ns = vim.api.nvim_create_namespace("notification-tools")
  for _, buf in pairs(initial) do
    for _, mark in
      ipairs(vim.api.nvim_buf_get_extmarks(buf, markdown_ns, 0, -1, { details = true }))
    do
      if mark[4].hl_group == "NotificationToolsBodyMarkdownBold" then
        local line = vim.api.nvim_buf_get_lines(buf, mark[2], mark[2] + 1, false)[1]
        strong = line:sub(mark[3] + 1, mark[4].end_col) == "Inlay Hints"
          and vim.api.nvim_get_hl(0, { name = mark[4].hl_group, link = false }).bold
      end
    end
  end
  assert(strong, "The screenshot's Inlay Hints text must actually be bold")
  for win in pairs(initial) do
    local position = vim.api.nvim_win_get_position(win)
    assert(position[2] > vim.o.columns / 3, "Float must be on the right")
  end
  vim.api.nvim_win_set_cursor(original_win, { 4, 0 })
  vim.api.nvim_feedkeys("i", "n", false)
end)
for i, char in ipairs({ "t", "y", "p", "i", "n", "g" }) do
  later(450 + i * 50, function()
    assert(vim.api.nvim_get_mode().mode:sub(1, 1) == "i", "Editor left Insert mode")
    vim.api.nvim_feedkeys(char, "n", false)
    waiting_changed = waiting_changed or preview_bar() ~= waiting_bar
    task:update({ percentage = 35 + i * 5 })
  end)
end
later(900, function()
  assert(vim.api.nvim_get_current_buf() == original_buf)
  assert(
    vim.api.nvim_buf_get_lines(original_buf, 3, 4, false)[1] == "typing",
    "Input was interrupted"
  )
  for win, buf in pairs(floats()) do
    assert(initial[win] == buf, "Progress updates recreated a window or buffer")
  end
  assert(waiting_changed, "Unknown-total bars must animate while editing")
  tools.notify("Updated notification", "info", { id = notice, title = "Build" })
  task:finish("Index ready")
  vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes("<Esc>", true, false, true), "n", false)
end)
later(1100, function()
  if failed then
    return
  end
  local text = screen()
  assert(text:find("Index ready", 1, true) and text:find("Updated notification", 1, true))
  snapshots.after = text
  local info = vim.api.nvim_get_hl(0, { name = "NotificationToolsINFO", link = false })
  local warn = vim.api.nvim_get_hl(0, { name = "NotificationToolsWARN", link = false })
  assert(info.fg and warn.fg and info.fg ~= warn.fg, "Severity colors must be visible and distinct")
end)
later(1450, function()
  snapshots.fading = screen()
  local found, active = false, false
  local ns = vim.api.nvim_create_namespace("notification-tools")
  for win, buf in pairs(floats()) do
    for _, mark in ipairs(vim.api.nvim_buf_get_extmarks(buf, ns, 0, -1, { details = true })) do
      local hl = mark[4].hl_group
      found = found or hl:find("TaskTitleFade", 1, true) ~= nil
      active = active or hl == "NotificationToolsTaskTitle"
    end
    assert(initial[win] == buf, "A fade recreated an existing float")
  end
  assert(found and active, "Only the completed task should fade")
end)
later(1750, function()
  if failed then
    return
  end
  snapshots.finished = screen()
  assert(#tools.tasks() == 1 and tools.tasks()[1].title == "Building document")
  for win, buf in pairs(floats()) do
    assert(initial[win] == buf, "Task expiry recreated a sibling float")
  end
  vim.fn.writefile(
    { vim.json.encode({ ok = true, theme = vim.g.colors_name, snapshots = snapshots }) },
    vim.env.NOTIFICATION_TOOLS_TUI_RESULT or "/private/tmp/notification-tools-tui.json"
  )
  if vim.env.NOTIFICATION_TOOLS_TUI_EXIT == "1" then
    vim.cmd("qa!")
  end
end)
