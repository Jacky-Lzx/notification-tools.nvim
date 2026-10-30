local h = dofile("tests/helpers.lua")
local tools = require("notification-tools")
local markdown = require("notification-tools.markdown")
local ns = vim.api.nvim_create_namespace("notification-tools")

-- The concealed source must produce exactly the same visible text as a popup,
-- including nested styles, partial delimiters, escapes and code span padding.
for _, text in ipairs({
  "Enabled **Inlay Hints**",
  "__bold__ and _italic_",
  "***both***",
  "**bold *italic***",
  "*italic **bold***",
  "**partial***",
  "***partial**",
  "中文 **粗体** 和 ~~删除~~",
  "Read [**文档**](https://example.com/a_(b))",
  "\\*literal\\* and `**code**`",
  "`` `tick` ``",
  "**` padded `**",
  "one\n\n_two_",
  "```lua\n'**literal**'\n```",
  "**open [unclosed](url",
}) do
  for _, enabled in ipairs({ true, false }) do
    local source = vim.split(text, "\n", { plain = true })
    local hidden = {}
    for _, mark in ipairs(markdown.source(text, "Body", enabled)) do
      assert(mark.col >= 0 and mark.finish <= #source[mark.row + 1])
      if mark.conceal then
        hidden[mark.row] = hidden[mark.row] or {}
        for col = mark.col, mark.finish - 1 do
          assert(not hidden[mark.row][col], "conceal ranges must not overlap")
          hidden[mark.row][col] = true
        end
      end
    end
    local visible = {}
    for row, line in ipairs(source) do
      local bytes = {}
      for col = 1, #line do
        if not (hidden[row - 1] and hidden[row - 1][col - 1]) then
          bytes[#bytes + 1] = line:sub(col, col)
        end
      end
      visible[row] = table.concat(bytes)
    end
    h.eq(markdown.text(markdown.parse(text, "Body", enabled)), table.concat(visible, "\n"))
  end
end

tools.setup({ notify = false, timeout = 0 })
local original_win = vim.api.nvim_get_current_win()
local conceallevel, concealcursor = vim.wo.conceallevel, vim.wo.concealcursor
local raw = "Enabled **Inlay Hints** and [中文文档](https://example.com/docs)"
local details = "Details: _中文_ and `a_b`"
tools.notify(raw, "warn", { title = "Hints", details = details })
tools.notify("literal **stars**", "error", { title = "Raw", markdown = false })
tools.show_history()
h.wait(function()
  return vim.bo.filetype == "notification-tools-history"
end)
local win, buf = vim.api.nvim_get_current_win(), vim.api.nvim_get_current_buf()
assert(not vim.bo[buf].modifiable and vim.wo[win].wrap)
h.eq(2, vim.wo[win].conceallevel)
h.eq("c", vim.wo[win].concealcursor)
h.eq(conceallevel, vim.wo[original_win].conceallevel)
h.eq(concealcursor, vim.wo[original_win].concealcursor)
local lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
h.eq("literal **stars**", lines[2])
h.eq(raw, lines[5])
h.eq(details, lines[6])
vim.api.nvim_win_set_cursor(win, { 5, 0 })
vim.api.nvim_feedkeys("yy", "xt", false)
h.eq(raw .. "\n", vim.fn.getreg('"'))
local highlighted, concealed = {}, {}
for _, mark in ipairs(vim.api.nvim_buf_get_extmarks(buf, ns, 0, -1, { details = true })) do
  local d = mark[4]
  highlighted[d.hl_group] = true
  if d.conceal == "" then
    concealed[#concealed + 1] = mark
  end
  if mark[2] == 1 then
    assert(d.conceal == nil, "per-notice opt-out must stay literal")
  end
end
for _, group in ipairs({
  "Meta",
  "Title",
  "WARN",
  "ERROR",
  "BodyMarkdownBold",
  "MetaMarkdownItalic",
  "MarkdownCode",
  "MarkdownLink",
}) do
  assert(highlighted["NotificationTools" .. group], "missing history color/style: " .. group)
end
assert(#concealed >= 6)
assert(vim.api.nvim_get_hl(0, { name = "NotificationToolsBodyMarkdownBold", link = false }).bold)
for _, mapping in ipairs(vim.api.nvim_buf_get_keymap(buf, "n")) do
  assert(mapping.lhs ~= "c", "history must not map c")
end
h.eq(lines, vim.api.nvim_buf_get_lines(buf, 0, -1, false))
h.eq(2, vim.wo[win].conceallevel)
-- A theme reload must rebuild derived Markdown styles for a history-only window.
tools.dismiss()
vim.wait(50, function()
  return false
end, 10)
vim.cmd.colorscheme("morning")
assert(vim.api.nvim_get_hl(0, { name = "NotificationToolsBodyMarkdownBold", link = false }).bold)
vim.cmd.colorscheme("evening")
assert(vim.api.nvim_get_hl(0, { name = "NotificationToolsBodyMarkdownBold", link = false }).bold)
h.eq(raw, tools.history()[1].message)
vim.api.nvim_feedkeys("q", "x", false)
h.eq(original_win, vim.api.nvim_get_current_win())
assert(
  not vim.api.nvim_buf_is_valid(buf),
  "closing history must release its buffer and decorations"
)
h.eq(conceallevel, vim.wo.conceallevel)
h.eq(concealcursor, vim.wo.concealcursor)
tools.clear_history()
tools.show_history()
h.wait(function()
  return vim.bo.filetype == "notification-tools-history"
end)
h.eq({ "No notifications" }, vim.api.nvim_buf_get_lines(0, 0, -1, false))
tools.teardown()
print(
  "history: source conceal, colors, nested Markdown, opt-out, theme reload, local options and cleanup passed"
)
