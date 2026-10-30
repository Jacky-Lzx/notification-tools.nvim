-- Run from the repository root with: nvim --headless -n -u NONE -i NONE --noplugin -l scripts/benchmark.lua
-- Microbenchmarks report timings; correctness tests deliberately have no speed thresholds.
vim.opt.runtimepath:prepend(vim.fn.getcwd())
local config = require("notification-tools.config").resolve({ notify = false })
local layout = require("notification-tools.layout")
local markdown = require("notification-tools.markdown")
local function measure(callback)
  for _ = 1, 3 do
    callback()
  end
  local samples = {}
  for index = 1, 30 do
    local started = vim.uv.hrtime()
    callback()
    samples[index] = (vim.uv.hrtime() - started) / 1e6
  end
  table.sort(samples)
  return { median_ms = samples[15], p95_ms = samples[29] }
end
local message = string.rep("workspace log output ", 5000)
local notice = {
  message = message,
  details = "",
  title = "Build",
  level = 2,
  markdown = true,
  time = os.time(),
  content_revision = 1,
}
local chunks = markdown.parse(message, "Body", true)
local report = {
  input_bytes = #message,
  max_body_rows = config.notification.window.max_height,
  neovim = tostring(vim.version()),
  cached_layout = measure(function()
    layout.notification(notice, config, 100, 20)
  end),
  bounded_wrap = measure(function()
    markdown.wrap(chunks, 54, 9)
  end),
}
local count = 0
report.metadata_update = measure(function()
  count = count + 1
  local updated = vim.tbl_extend("force", {}, notice, { count = count })
  layout.notification(updated, config, 100, 20)
end)
print(vim.json.encode(report))
