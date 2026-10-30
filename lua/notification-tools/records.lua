local M = {}
local levels = require("notification-tools.config")

function M.options(opts)
  assert(opts == nil or type(opts) == "table", "history options must be a table")
  opts = vim.deepcopy(opts or {})
  if opts.level ~= nil then
    opts.level = levels.level(opts.level)
  end
  for _, key in ipairs({ "source", "title" }) do
    assert(opts[key] == nil or type(opts[key]) == "string", key .. " must be a string")
  end
  return opts
end

function M.filter(items, opts)
  opts = M.options(opts)
  return vim.tbl_filter(function(item)
    return (not opts.level or item.level >= opts.level)
      and (not opts.source or (item.source or item.title) == opts.source)
      and (not opts.title or item.title:lower():find(opts.title:lower(), 1, true) ~= nil)
  end, items)
end

return M
