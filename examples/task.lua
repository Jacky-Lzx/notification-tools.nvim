-- Consumer-side integration: the producer owns its events, cancellation and handles.
local tools = require("notification-tools")
local task = tools.progress({
  id = "my-plugin:build:1", -- Namespace IDs to avoid colliding with other producers.
  title = "Building document",
  source = "my-plugin",
  percentage = 0,
  message = "Starting…",
})

-- Call these methods from the producer's own callbacks.
task:update({ percentage = 60, message = "Compiling references" })
task:finish("PDF ready")
-- Alternatively: task:finish("Compiler failed", "error") or task:cancel().

return task
