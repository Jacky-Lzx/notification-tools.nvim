local h = dofile("tests/helpers.lua")
local tools = require("notification-tools")
local content = require("notification-tools.content")
local markdown = require("notification-tools.markdown")
local api = vim.api
local raw = "Header\t中文\n{ enabled = true, text = '**literal**' }\nWarning!"
local start = assert(raw:find("{", 1, true)) - 1
local finish = assert(raw:find("\nWarning!", 1, true)) - 1
local spans = {
  { start = start, finish = finish, filetype = "lua" },
  { start = finish + 1, finish = #raw, hl_group = "WarningMsg" },
}
local chunks, marks = content.parse(raw, "Body", false, nil, true, spans)
local clean = require("notification-tools.text").clean(raw)
h.eq(clean, markdown.text(chunks))
local lines = vim.split(clean, "\n", { plain = true })
local found = {}
for _, mark in ipairs(marks) do
  local text = lines[mark.row + 1]:sub(mark.col + 1, mark.finish)
  found[text] = mark.hl
end
h.eq("LuaBoolean", found["true"])
h.eq("LuaString", found["'**literal**'"])
local external = found["Warning!"]
assert(external and external:find("External", 1, true))
local theme = require("notification-tools.theme")
h.eq(theme.definition("WarningMsg"), theme.definition("NotificationTools" .. external))

tools.setup({ notify = false, timeout = 0 })
local id = tools.notify(raw, "info", { markdown = false, spans = spans })
local item = tools.history()[1]
h.eq(spans, item.spans)
spans[1].filetype = "text"
h.eq("lua", tools.history()[1].spans[1].filetype)
local other = tools.notify(raw, "info", { markdown = false, spans = spans })
assert(other ~= id)
local revision = tools.history()[1].content_revision
tools.notify(raw, "info", { id = id, markdown = false, spans = spans })
assert(revision ~= tools.history()[#tools.history()].content_revision)
-- Formatting is inferred anew on replacement, including removal of spans.
tools.notify(raw, nil, { id = id })
h.eq(nil, tools.history()[#tools.history()].spans)
for _, invalid in ipairs({
  { { start = -1, finish = 1, filetype = "lua" } },
  { { start = 0, finish = #raw + 1, filetype = "lua" } },
  { { start = 1, finish = 1, filetype = "lua" } },
  { { start = 0, finish = 1, filetype = "python" } },
  { { start = 0, finish = 1, filetype = "lua", hl_group = "String" } },
  { { start = 0, finish = 3, filetype = "lua" }, { start = 2, finish = 4, filetype = "lua" } },
  { { start = 0, finish = 8, filetype = "lua" } }, -- Splits the first Chinese character.
}) do
  assert(not pcall(tools.notify, raw, nil, { spans = invalid }), vim.inspect(invalid))
end
-- Native chunks retain group identity through append, replace and history import.
local attach, detach, callback = vim.ui_attach, vim.ui_detach
vim.ui_attach = function(_, _, fn)
  callback = fn
end
vim.ui_detach = function() end
tools.setup({ notify = false, timeout = 0, messages = { enabled = true } })
local lease = tools.attach_messages()
local warning = api.nvim_get_hl_id_by_name("WarningMsg")
local number = api.nvim_get_hl_id_by_name("Number")
callback("msg_show", "echo", { { 99, "中文\t", warning }, { 0, "plain" } }, false, true, false, 1)
callback("msg_show", "echo", { { 42, "\n42", number } }, true, true, true, 1)
h.wait(function()
  return #tools.history() == 1 and tools.history()[1].message:find("42", 1, true)
end)
item = tools.history()[1]
h.eq("中文\tplain\n42", item.message)
h.eq({
  { start = 0, finish = 7, hl_group = "WarningMsg" },
  { start = 12, finish = 15, hl_group = "Number" },
}, item.spans)
callback("msg_show", "echo", { { 0, "replacement" } }, true, true, false, 1)
h.wait(function()
  return tools.history()[1].message == "replacement"
end)
h.eq(nil, tools.history()[1].spans)
lease:detach()
vim.ui_attach, vim.ui_detach = attach, detach
tools.teardown()
print(
  "spans: mixed Lua/text, raw byte offsets, native colors, replacement isolation and validation passed"
)
