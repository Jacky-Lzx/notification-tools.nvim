-- One content dispatch for wrapped popups and original-source readers.
local M = {}

function M.parse(value, base, markdown, filetype, source)
  if filetype == "lua" then
    return require("notification-tools.lua").parse(value, base, source)
  end
  if filetype == "text" then
    markdown = false
  end
  return require("notification-tools.markdown").parse(value, base, markdown, source)
end

function M.source(value, base, markdown, filetype)
  if filetype ~= "lua" then
    if filetype == "text" then
      markdown = false
    end
    return require("notification-tools.markdown").source(value, base, markdown)
  end
  local _, spans = M.parse(value, base, markdown, filetype, true)
  return spans
end

return M
