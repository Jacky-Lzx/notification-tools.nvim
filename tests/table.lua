local h = dofile("tests/helpers.lua")
local tools = require("notification-tools")
local content = require("notification-tools.content")
local markdown = require("notification-tools.markdown")
local api = vim.api
local ns = api.nvim_create_namespace("notification-tools")

local sample = {
  enabled = true,
  disabled = false,
  count = -12.5e20,
  text = '**literal** _under_score_ 中文🙂é "quoted" \\ slash\nnext',
  nested = { 42, "value" },
  callback = function() end,
  infinity = math.huge,
  nan = 0 / 0,
}
sample.self = sample
local raw = vim.inspect(sample)
local chunks, spans = content.parse(raw, "Body", true, "lua", true)
h.eq(raw, markdown.text(chunks))
local source_lines = vim.split(raw, "\n", { plain = true })
local tokens = {}
for _, mark in ipairs(spans) do
  assert(mark.col >= 0 and mark.finish <= #source_lines[mark.row + 1])
  tokens[mark.hl] = (tokens[mark.hl] or "")
    .. source_lines[mark.row + 1]:sub(mark.col + 1, mark.finish)
end
assert(tokens.LuaField:find("enabled", 1, true))
assert(tokens.LuaString:find("**literal** _under_score_", 1, true))
assert(tokens.LuaNumber:find("inf", 1, true) and tokens.LuaNumber:find("nan", 1, true))
assert(tokens.LuaBoolean:find("true", 1, true) and tokens.LuaBoolean:find("false", 1, true))
assert(tokens.LuaSpecial:find("<table 1>", 1, true))
assert(tokens.LuaSpecial:find("<function 1>", 1, true))
assert(not tokens.MarkdownCode)

-- Multiline tokens keep source rows/byte columns, including empty lines and UTF-8.
local code = "local x = [=[中文\n\n🙂]=]\n--[=[comment\nline]=]\nreturn nil, .5, 0xff, 1e-3"
local _, marks = content.parse(code, "Body", true, "lua", true)
local lines = vim.split(code, "\n", { plain = true })
local seen = {}
for _, mark in ipairs(marks) do
  local text = lines[mark.row + 1]:sub(mark.col + 1, mark.finish)
  seen[text] = mark.hl
end
h.eq("LuaString", seen["[=[中文"])
h.eq("LuaString", seen["🙂]=]"])
h.eq("LuaComment", seen["--[=[comment"])
h.eq("LuaComment", seen["line]=]"])
h.eq("LuaSpecial", seen["nil"])
h.eq("LuaNumber", seen[".5"])
h.eq("LuaNumber", seen["0xff"])
h.eq("LuaNumber", seen["1e-3"])
for _, text in ipairs({ "'unfinished\\", "[=[unfinished\n", "<table 1", "-- comment", "" }) do
  h.eq(text, markdown.text(content.parse(text, "Body", true, "lua")))
end

-- Highlight chunks must survive narrow Unicode wrapping and truncation.
for width = 1, 24 do
  for _, line in ipairs(markdown.wrap(chunks, width)) do
    assert(vim.fn.strdisplaywidth(markdown.text(line)) <= width)
  end
end
local large = vim.inspect(vim.fn.range(1, 10000))
h.eq(large, markdown.text(content.parse(large, "Body", true, "lua")))
local digits = string.rep("1", 100000)
h.eq(digits, markdown.text(content.parse(digits, "Body", true, "lua")))

vim.o.columns, vim.o.lines = 100, 40
tools.setup({ notify = true, timeout = 0, notification = { timestamp = false } })
local id = vim.notify(sample, "info", { details = "**detail**" })
local item = tools.history()[1]
h.eq("lua", item.filetype)
h.eq(raw, item.message)
sample.enabled = false
h.eq(raw, tools.history()[1].message) -- Snapshots never retain the caller's table.
local function groups(buf)
  local found = {}
  for _, mark in ipairs(api.nvim_buf_get_extmarks(buf, ns, 0, -1, { details = true })) do
    found[mark[4].hl_group] = true
  end
  return found
end
h.wait(function()
  return #h.floats() == 1 and groups(h.floats()[1].buf).NotificationToolsLuaBoolean
end)
local original_win = h.floats()[1].win
tools.show_history()
h.wait(function()
  return vim.bo.filetype == "notification-tools-history"
end)
local history_buf = api.nvim_get_current_buf()
assert(groups(history_buf).NotificationToolsLuaString)
assert(groups(history_buf).NotificationToolsLuaSpecial)
assert(groups(history_buf).NotificationToolsMetaMarkdownBold, "details retain their own Markdown")
assert(table.concat(api.nvim_buf_get_lines(history_buf, 0, -1, false), "\n"):find(raw, 1, true))
api.nvim_feedkeys("q", "xt", false)
tools.show_history()
h.wait(function()
  return vim.bo.filetype == "notification-tools-history"
end)
history_buf = api.nvim_get_current_buf()

-- Equal text with different formats neither merges nor reuses stale parsed plans.
local literal = tools.notify(raw, "info", { markdown = true, details = "**detail**" })
assert(literal ~= id)
local revision = tools.history()[1].content_revision
tools.notify(raw, nil, { id = id })
item = tools.history()[#tools.history()]
h.eq(nil, item.filetype)
assert(revision ~= item.content_revision)
api.nvim_feedkeys("r", "xt", false)
assert(not groups(history_buf).NotificationToolsLuaBoolean, "refresh must invalidate body format")
api.nvim_feedkeys("q", "xt", false)
h.wait(function()
  for _, entry in ipairs(h.floats()) do
    if entry.win == original_win then
      return not groups(entry.buf).NotificationToolsLuaBoolean
    end
  end
end)
tools.notify({ enabled = true }, nil, { id = id })
h.wait(function()
  for _, entry in ipairs(h.floats()) do
    if entry.win == original_win then
      return groups(entry.buf).NotificationToolsLuaBoolean
    end
  end
end)

tools.setup({ notify = false, timeout = 0, notification = { markdown = false } })
id = tools.notify({ enabled = true })
h.eq("lua", tools.history()[1].filetype)
local duplicate = tools.notify({ enabled = true })
h.eq(id, duplicate)
h.eq(2, tools.history()[1].count)
local plain = tools.notify({ enabled = true }, nil, { filetype = "text" })
assert(plain ~= id)
h.eq("text", tools.history()[2].filetype)
local explicit = tools.notify(vim.inspect({ enabled = true }), nil, { filetype = "lua" })
h.eq(id, explicit)
h.wait(function()
  local colored, uncolored = false, false
  for _, entry in ipairs(h.floats()) do
    if groups(entry.buf).NotificationToolsLuaBoolean then
      colored = true
    else
      uncolored = true
    end
  end
  return colored and uncolored
end)
assert(not pcall(tools.notify, {}, nil, { filetype = "python" }))
assert(not pcall(tools.notify, {}, nil, { filetype = false }))
tools.teardown()
print(
  "table: automatic Lua colors, special inspect values, source spans, wrapping, replacements and format isolation passed"
)
