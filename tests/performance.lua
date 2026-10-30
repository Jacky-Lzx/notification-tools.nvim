local h = dofile("tests/helpers.lua")
local text = require("notification-tools.text")
local markdown = require("notification-tools.markdown")
local layout = require("notification-tools.layout")
local tools = require("notification-tools")
local config = require("notification-tools.config").resolve({ notify = false })

-- Segmentation must remain exactly Neovim's, including clusters crossing batches.
for _, suffix in ipairs({
  "é",
  "👨‍👩‍👧‍👦",
  "🇬🇧🇫🇷",
  "👍🏽",
  "e" .. string.rep("́", 1200),
}) do
  local value = string.rep("a", 1023) .. suffix .. "\nend"
  local chars = {}
  for char in text.chars(value) do
    chars[#chars + 1] = char
  end
  h.eq(vim.fn.split(value, "\\zs"), chars)
end
local huge = string.rep("a", 105000)
local split, largest = vim.fn.split, 0
vim.fn.split = function(value, ...)
  largest = math.max(largest, #value)
  return split(value, ...)
end
local lines = markdown.wrap({ { huge, "Body" } }, 54, 9)
h.eq(9, #lines)
assert(largest <= 1028, "a bounded preview must not split the entire input")
h.eq(huge, markdown.text({ { huge, "Body" } }))
vim.fn.split = split

tools.setup({ notify = false, timeout = 0 })
local parses, parse = 0, markdown.parse
markdown.parse = function(...)
  parses = parses + 1
  return parse(...)
end
local id = tools.notify("**Stable content**", "info", { title = "Build" })
h.wait(function()
  return #h.floats() == 1
end)
local original = parses
tools.notify("**Stable content**", "info", { title = "Build" })
h.wait(function()
  return tools.history()[1].count == 2
    and table.concat(h.floats()[1].lines, "\n"):find("×2", 1, true) ~= nil
end)
h.eq(original, parses)
tools.notify("**Stable content**", nil, { id = id, title = "Renamed" })
h.wait(function()
  return table.concat(h.floats()[1].lines, "\n"):find("Renamed", 1, true) ~= nil
end)
h.eq(original, parses)
tools.notify("**Changed content**", nil, { id = id })
h.wait(function()
  return parses > original
end)
h.eq("**Changed content**", tools.history()[1].message)
markdown.parse = parse
tools.teardown()

local item =
  { message = huge, details = "", title = "Build", level = 2, markdown = true, time = os.time() }
local plan = layout.notification(item, config, 100, 20)
local widths, measure = 0, vim.fn.strdisplaywidth
vim.fn.strdisplaywidth = function(...)
  widths = widths + 1
  return measure(...)
end
h.eq(plan, layout.notification(item, config, 100, 20))
h.eq(0, widths)
assert(layout.notification(item, config, 30, 20).width <= 30)
assert(widths > 0, "screen constraints must invalidate layout caches")
vim.fn.strdisplaywidth = measure
local saved = vim.fn.getcellwidths()
vim.fn.setcellwidths({ { 0x2500, 0x257f, 2 } })
layout.notification(item, config, 100, 20)
vim.fn.setcellwidths(saved)
print(
  "performance: bounded previews, native grapheme boundaries, metadata cache reuse and geometry invalidation passed"
)
