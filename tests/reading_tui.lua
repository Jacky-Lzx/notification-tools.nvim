-- nvim -n -u tests/reading_tui.lua -i NONE (same environment as history_tui.lua).
vim.opt.runtimepath:prepend(vim.fn.getcwd())
vim.o.termguicolors, vim.o.swapfile = true, false
local theme = vim.env.NOTIFICATION_TOOLS_THEME_ROOT
if theme and theme ~= "" then
  vim.opt.runtimepath:append(theme)
  require("catppuccin").setup({ flavour = "mocha" })
  vim.cmd.colorscheme("catppuccin")
end
local tools = require("notification-tools")
tools.setup({ timeout = 700 })
local original_win = vim.api.nvim_get_current_win()
local snapshots, failed, reader_buf = {}, false, nil
local function floats()
  local result = {}
  for _, win in ipairs(vim.api.nvim_list_wins()) do
    if vim.bo[vim.api.nvim_win_get_buf(win)].filetype == "notification-tools" then
      result[#result + 1] = win
    end
  end
  return result
end
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
    vim.env.NOTIFICATION_TOOLS_TUI_RESULT or "/private/tmp/notification-tools-reading-tui.json"
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
  tools.notify(
    "Enabled **Inlay Hints**\n" .. string.rep("long body\n", 30) .. "last line",
    "info",
    { title = "Long", source = "compiler" }
  )
end)
later(350, function()
  vim.cmd("NotificationsLatest")
end)
later(550, function()
  assert(vim.b.notification_tools_detail)
  reader_buf = vim.api.nvim_get_current_buf()
  assert(vim.api.nvim_buf_get_lines(reader_buf, -3, -1, false)[1] == "last line")
  local reader_z = vim.api.nvim_win_get_config(0).zindex
  for _, win in ipairs(floats()) do
    assert(reader_z > vim.api.nvim_win_get_config(win).zindex)
  end
  snapshots.concealed = screen()
  assert(snapshots.concealed:find("Enabled Inlay Hints", 1, true))
  assert(not snapshots.concealed:find("**Inlay Hints**", 1, true))
  vim.api.nvim_input("j")
end)
later(750, function()
  snapshots.revealed = screen()
  assert(snapshots.revealed:find("**Inlay Hints**", 1, true))
end)
later(1100, function()
  assert(#floats() == 1, "reading must pause the original timeout")
  assert(vim.api.nvim_buf_is_valid(reader_buf))
end)
later(1400, function()
  vim.api.nvim_input("q")
end)
later(1550, function()
  assert(vim.api.nvim_get_current_win() == original_win)
  assert(not vim.api.nvim_buf_is_valid(reader_buf))
  assert(#floats() == 1, "closing resumes remaining time")
end)
later(2050, function()
  assert(#floats() == 0, "remaining timeout must eventually expire")
  tools.notify(
    "filter warning",
    "warn",
    { title = "Compiler warning", source = "compiler", timeout = 0 }
  )
  tools.dismiss()
  tools.show_history({ source = "compiler" })
end)
later(2250, function()
  vim.api.nvim_input("gl")
end)
later(2400, function()
  snapshots.level_prompt = screen()
  assert(snapshots.level_prompt:find("Minimum notification level", 1, true))
  vim.api.nvim_input("5\r") -- built-in vim.ui.select: WARN
end)
later(2650, function()
  snapshots.filtered = screen()
  assert(snapshots.filtered:find("WARN+", 1, true))
  assert(snapshots.filtered:find("filter warning", 1, true))
  assert(not snapshots.filtered:find("Enabled", 1, true))
  vim.api.nvim_input("\r")
end)
later(2850, function()
  assert(vim.b.notification_tools_detail)
  snapshots.selection = screen()
  assert(snapshots.selection:find("filter warning", 1, true))
  vim.api.nvim_input("q")
end)
later(3050, function()
  assert(vim.api.nvim_get_current_win() == original_win)
  tools.teardown()
  result(true)
end)
