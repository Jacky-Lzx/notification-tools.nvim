local h = dofile("tests/helpers.lua")
local tools = require("notification-tools")
local ns = vim.api.nvim_create_namespace("notification-tools")
tools.setup({
  notify = false,
  progress = { stale_timeout = 0, window = { min_width = 44, max_width = 44 } },
})
local task =
  tools.progress({ title = "Build", source = "Stable source", percentage = 5, message = "Working" })
tools.progress({ title = "Sibling", source = "Stable source", percentage = 10 })
h.wait(function()
  return #h.floats() == 1
end)
local buf = h.floats()[1].buf
local function source_id()
  for _, mark in ipairs(vim.api.nvim_buf_get_extmarks(buf, ns, 0, -1, { details = true })) do
    if mark[4].hl_group == "NotificationToolsSource" then
      return mark[1]
    end
  end
end
local source = assert(source_id())
local writes, set_lines = {}, vim.api.nvim_buf_set_lines
vim.api.nvim_buf_set_lines = function(buffer, first, last, ...)
  if buffer == buf then
    writes[#writes + 1] = { first, last }
  end
  return set_lines(buffer, first, last, ...)
end
task:update({ percentage = 65 })
h.wait(function()
  return table.concat(h.floats()[1].lines, "\n"):find("65%%") ~= nil
end)
h.eq(source, source_id())
assert(#writes > 0)
for _, range in ipairs(writes) do
  assert(range[1] > 0 and range[2] == range[1] + 1, "update only changed task rows")
end
for _, mark in ipairs(vim.api.nvim_buf_get_extmarks(buf, ns, 0, -1, { details = true })) do
  local line = vim.api.nvim_buf_get_lines(buf, mark[2], mark[2] + 1, false)[1]
  assert(mark[3] < #line and mark[4].end_col <= #line)
end
vim.api.nvim_buf_set_lines = set_lines
tools.teardown()
print("incremental: task updates preserve unrelated rows and extmark identities")
