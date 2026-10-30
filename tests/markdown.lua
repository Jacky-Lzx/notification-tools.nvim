local h = dofile("tests/helpers.lua")
local markdown = require("notification-tools.markdown")
local tools = require("notification-tools")
local ns = vim.api.nvim_create_namespace("notification-tools")
local function render(text)
  return markdown.text(markdown.parse(text))
end
local function styled_text(text, style, group)
  local pieces = {}
  for _, chunk in ipairs(markdown.parse(text)) do
    if (not style or chunk[3] == style) and (not group or chunk[2] == group) then
      pieces[#pieces + 1] = chunk[1]
    end
  end
  return table.concat(pieces)
end
for _, case in ipairs({
  { "Enabled **Inlay Hints**", "Enabled Inlay Hints" },
  { "__bold__ and _italic_", "bold and italic" },
  { "**bold *italic***", "bold italic" },
  { "*italic **bold***", "italic bold" },
  { "***both***", "both" },
  { "~~old~~ **new**", "old new" },
  { "`**literal**`", "**literal**" },
  { "`` `tick` ``", "`tick`" },
  { "**`a_b`**", "a_b" },
  { "foo_bar_baz", "foo_bar_baz" },
  { "_中文_。", "中文。" },
  { "\\*literal\\*", "*literal*" },
  { "`\\*literal*`", "\\*literal*" },
  { "[**guide**](https://example.com/a_(b))", "guide" },
  { "[broken](url", "[broken](url" },
  { "**open", "**open" },
  { "unclosed `code", "unclosed `code" },
  { "**中文**\n\n`a_b`", "中文\n\na_b" },
  { "```lua\nlocal x = '**literal**'\n```", "```lua\nlocal x = '**literal**'\n```" },
}) do
  h.eq(case[2], render(case[1]))
end
h.eq("Inlay Hints", styled_text("Enabled **Inlay Hints**", "Bold"))
h.eq("italic", styled_text("**bold *italic***", "BoldItalic"))
h.eq("both", styled_text("***both***", "BoldItalic"))
h.eq("old", styled_text("~~old~~", "Strike"))
h.eq("**literal**", styled_text("`**literal**`", nil, "MarkdownCode"))
h.eq("guide", styled_text("[**guide**](url)", "Bold", "MarkdownLink"))

local multiline = markdown.wrap(markdown.parse("**one**\n\n_two_"), 10)
h.eq(3, #multiline)
h.eq("one", markdown.text(multiline[1]))
h.eq("", markdown.text(multiline[2]))
h.eq("two", markdown.text(multiline[3]))
local sample =
  "普通 **中文 é🦀加粗** _斜体_ `a_b` ~~删除~~ [文档](https://example.com)"
for _, ambiwidth in ipairs({ "single", "double" }) do
  vim.o.ambiwidth = ambiwidth
  for width = 1, 24 do
    local chunks = markdown.parse(sample)
    for _, line in ipairs(markdown.wrap(chunks, width)) do
      assert(vim.fn.strdisplaywidth(markdown.text(line)) <= width)
    end
    assert(vim.fn.strdisplaywidth(markdown.text(markdown.clip(chunks, width))) <= width)
  end
end
vim.o.ambiwidth = "single"
local oversized = string.rep("[", 2000) .. " unmatched"
h.eq(oversized, render(oversized))

vim.o.columns, vim.o.lines = 100, 32
tools.setup({
  notify = false,
  timeout = 0,
  notification = { timestamp = false },
  window = { min_width = 1, max_width = 60 },
})
local raw = "Enabled **Inlay Hints**"
local id = tools.notify(raw, "info", { title = "Hints" })
h.wait(function()
  return #h.floats() == 1
end)
local entry = h.floats()[1]
local visible = table.concat(entry.lines, "\n")
assert(visible:find("Enabled Inlay Hints", 1, true) and not visible:find("**", 1, true))
h.eq(raw, tools.history()[1].message)
-- Width uses rendered cells, rather than counting the four hidden stars.
h.eq(vim.fn.strdisplaywidth("Enabled Inlay Hints") + 6, entry.config.width)
local bold
for _, mark in ipairs(vim.api.nvim_buf_get_extmarks(entry.buf, ns, 0, -1, { details = true })) do
  if mark[4].hl_group == "NotificationToolsBodyMarkdownBold" then
    bold = mark
  end
end
assert(bold and vim.api.nvim_get_hl(0, { name = bold[4].hl_group, link = false }).bold)
h.eq("Inlay Hints", entry.lines[bold[2] + 1]:sub(bold[3] + 1, bold[4].end_col))
local original_win = entry.win
tools.notify(
  "已启用 **中文 Inlay Hints** 和 `code`",
  "info",
  { id = id, details = "Read [guide](url)" }
)
h.wait(function()
  return table.concat(h.floats()[1].lines, "\n"):find("已启用", 1, true) ~= nil
end)
h.eq(original_win, h.floats()[1].win)
tools.show_history()
h.wait(function()
  return vim.bo.filetype == "notification-tools-history"
end)
assert(
  table
    .concat(vim.api.nvim_buf_get_lines(0, 0, -1, false), "\n")
    :find("**中文 Inlay Hints**", 1, true)
)
vim.api.nvim_feedkeys("q", "x", false)

tools.setup({
  notify = false,
  timeout = 0,
  window = { min_width = 10, max_width = 20 },
  notification = { timestamp = false },
})
tools.notify("前缀 **中文粗体中文粗体中文粗体** suffix", "info", { title = "Wrap" })
h.wait(function()
  return #h.floats() == 1
end)
entry = h.floats()[1]
local bold_rows = {}
for _, mark in ipairs(vim.api.nvim_buf_get_extmarks(entry.buf, ns, 0, -1, { details = true })) do
  if mark[4].hl_group == "NotificationToolsBodyMarkdownBold" then
    bold_rows[mark[2]] = true
  end
end
assert(vim.tbl_count(bold_rows) >= 2, "a wrapped strong span must stay bold on each line")
tools.setup({
  notify = false,
  timeout = 0,
  window = { min_width = 10, max_width = 20, max_height = 1 },
})
tools.notify("**abcdefghijklmnopqrstuvwxyz**")
h.wait(function()
  return #h.floats() == 1
end)
entry = h.floats()[1]
assert(table.concat(entry.lines, "\n"):find("…", 1, true))
assert(not table.concat(entry.lines, "\n"):find("**", 1, true))

tools.setup({ notify = false, timeout = 0, notification = { markdown = false } })
local plain = tools.notify(raw)
local rich = tools.notify(raw, nil, { markdown = true })
assert(plain ~= rich, "plain and formatted notices must not merge")
h.wait(function()
  return #h.floats() == 2
end)
local plain_seen, rich_seen = false, false
for _, item in ipairs(h.floats()) do
  local text = table.concat(item.lines, "\n")
  plain_seen = plain_seen or text:find(raw, 1, true) ~= nil
  rich_seen = rich_seen or text:find("Enabled Inlay Hints", 1, true) ~= nil
end
assert(plain_seen and rich_seen)
tools.notify("Updated **literal**", nil, { id = plain })
h.eq(false, tools.history()[2].markdown)
assert(not pcall(tools.notify, "bad", nil, { markdown = "yes" }))
assert(not pcall(tools.setup, { notification = { markdown = "yes" } }))
tools.teardown()
print(
  "markdown: screenshot case, inline styles, escaping, code/links, Unicode wrap, source history and opt-out passed"
)
