-- Run from the plugin root: nvim -n -u tests/history_tui.lua -i NONE
vim.opt.runtimepath:prepend(vim.fn.getcwd())
vim.o.termguicolors = true
vim.o.swapfile = false
local theme = vim.env.NOTIFICATION_TOOLS_THEME_ROOT
if theme and theme ~= "" then
  vim.opt.runtimepath:append(theme)
  require("catppuccin").setup({ flavour = "mocha" })
  vim.cmd.colorscheme("catppuccin")
end
local tools = require("notification-tools")
tools.setup({ timeout = 0 })
local original_win = vim.api.nvim_get_current_win()
local original_conceal, original_cursor = vim.wo.conceallevel, vim.wo.concealcursor
local raw = "Enabled **Inlay Hints**; _中文_ and `code` [guide](https://example.com)"
local history_buf, snapshots, failed = nil, {}, false
local function screen()
  vim.cmd.redraw()
  local lines = {}
  for row = 1, vim.o.lines do
    local cells = {}
    for col = 1, vim.o.columns do
      cells[#cells + 1] = vim.fn.screenstring(row, col)
    end
    lines[row] = table.concat(cells)
  end
  return table.concat(lines, "\n")
end
local function result(ok, err)
  vim.fn.writefile(
    { vim.json.encode({ ok = ok, error = err, theme = vim.g.colors_name, snapshots = snapshots }) },
    vim.env.NOTIFICATION_TOOLS_TUI_RESULT or "/private/tmp/notification-tools-history-tui.json"
  )
  if vim.env.NOTIFICATION_TOOLS_TUI_EXIT == "1" then
    vim.cmd(ok and "qa!" or "cquit 1")
  end
end
local function later(delay, callback)
  vim.defer_fn(function()
    if failed then
      return
    end
    local ok, err = xpcall(callback, debug.traceback)
    if not ok then
      failed = true
      result(false, err)
    end
  end, delay)
end
later(150, function()
  assert(#vim.api.nvim_list_uis() > 0)
  tools.notify(raw, "warn", { title = "Hints", details = "Details: **已启用**" })
  tools.notify("An error message", "error", { title = "Build" })
  tools.dismiss()
  tools.show_history()
end)
later(400, function()
  assert(vim.bo.filetype == "notification-tools-history")
  history_buf = vim.api.nvim_get_current_buf()
  vim.api.nvim_win_set_cursor(0, { 1, 0 })
  snapshots.concealed = screen()
  assert(snapshots.concealed:find("Enabled Inlay Hints", 1, true))
  assert(not snapshots.concealed:find("**Inlay Hints**", 1, true))
  assert(not snapshots.concealed:find("https://example.com", 1, true))
  local strong, warning, error = false, false, false
  for _, mark in
    ipairs(
      vim.api.nvim_buf_get_extmarks(
        history_buf,
        vim.api.nvim_create_namespace("notification-tools"),
        0,
        -1,
        { details = true }
      )
    )
  do
    local group = mark[4].hl_group
    strong = strong
      or (
        group == "NotificationToolsBodyMarkdownBold"
        and vim.api.nvim_get_hl(0, { name = group, link = false }).bold
      )
    warning = warning or group == "NotificationToolsWARN"
    error = error or group == "NotificationToolsERROR"
  end
  assert(strong and warning and error)
  local warn_color = vim.api.nvim_get_hl(0, { name = "NotificationToolsWARN", link = false }).fg
  local error_color = vim.api.nvim_get_hl(0, { name = "NotificationToolsERROR", link = false }).fg
  assert(warn_color and error_color and warn_color ~= error_color)
  vim.api.nvim_win_set_cursor(0, { 2, 0 })
end)
later(600, function()
  snapshots.cursor_line = screen()
  assert(vim.wo.conceallevel == 2 and vim.wo.concealcursor == "c")
  assert(snapshots.cursor_line:find("**Inlay Hints**", 1, true))
  assert(snapshots.cursor_line:find("https://example.com", 1, true))
  assert(
    not snapshots.cursor_line:find("**已启用**", 1, true),
    "other lines must remain concealed"
  )
  vim.api.nvim_win_set_cursor(0, { 3, 0 })
end)
later(800, function()
  snapshots.cursor_moved = screen()
  assert(snapshots.cursor_moved:find("Enabled Inlay Hints", 1, true))
  assert(
    not snapshots.cursor_moved:find("**Inlay Hints**", 1, true),
    "the previous cursor line must conceal again"
  )
  assert(snapshots.cursor_moved:find("**已启用**", 1, true))
  vim.api.nvim_win_set_cursor(0, { 1, 0 })
  vim.api.nvim_input("c")
end)
later(1000, function()
  snapshots.source = screen()
  assert(vim.wo.conceallevel == 0)
  assert(snapshots.source:find("**Inlay Hints**", 1, true))
  assert(snapshots.source:find("https://example.com", 1, true))
  assert(vim.api.nvim_buf_get_lines(history_buf, 1, 2, false)[1] == raw)
  vim.api.nvim_input("c")
end)
later(1200, function()
  snapshots.reconcealed = screen()
  assert(vim.wo.conceallevel == 2)
  assert(snapshots.reconcealed:find("Enabled Inlay Hints", 1, true))
  assert(not snapshots.reconcealed:find("**Inlay Hints**", 1, true))
  vim.api.nvim_input("q")
end)
later(1400, function()
  assert(vim.api.nvim_get_current_win() == original_win)
  assert(vim.wo.conceallevel == original_conceal and vim.wo.concealcursor == original_cursor)
  assert(not vim.api.nvim_buf_is_valid(history_buf))
  assert(tools.history()[1].message == raw)
  result(true)
end)
