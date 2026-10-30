-- Consumer-side handoff; notification-tools does not render command lines.
-- Set messages.enabled=true in notification-tools setup first.
local M = {}
local handle

-- Call only AFTER the consumer's cmdline/prompt renderer is fully attached.
-- It must own cmdline_*, completion, interactive msg_show prompts and status
-- widgets. It must not consume the non-interactive messages handed over here.
function M.ready()
  if not handle or not handle:is_active() then
    handle = require("notification-tools").attach_messages()
  end
end

-- Call BEFORE detaching/stopping that renderer (also on consumer failure).
function M.stopping()
  if handle then
    handle:detach()
    handle = nil
  end
end

-- notification-tools setup()/teardown() invalidate the old handle. If a
-- consumer stays running through reconfiguration, call ready() again afterward.
return M
