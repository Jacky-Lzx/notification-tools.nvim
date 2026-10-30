local M = {}

M.defaults = {
  notify = true,
  level = vim.log.levels.INFO,
  timeout = 4000,
  history_size = 200,
  max_notifications = 5,
  max_pending = 100,
  window = {
    border = "rounded",
    winblend = 0,
    max_width = 60,
    min_width = 24,
    max_height = 8,
    top = 1,
    right = 1,
    bottom = 1,
    zindex = 150,
  },
  progress = {
    enabled = true,
    max_items = 6,
    done_ttl = 1500,
    stale_timeout = 120000,
    interval = 80,
    avoid = { "NvimTree", "TestExplorer" },
    spinner = { "⠋", "⠙", "⠹", "⠸", "⠼", "⠴", "⠦", "⠧", "⠇", "⠏" },
  },
  lsp = { enabled = true, ignore = {} },
  icons = { ERROR = "✖", WARN = "▲", INFO = "●", DEBUG = "◆", TRACE = "·" },
}

function M.level(value)
  if type(value) == "string" then
    value = vim.log.levels[value:upper() == "WARNING" and "WARN" or value:upper()]
  end
  assert(
    type(value) == "number" and value >= 0 and value <= 5 and value == math.floor(value),
    "invalid notification level"
  )
  return value
end

function M.resolve(opts)
  local config = vim.tbl_deep_extend("force", vim.deepcopy(M.defaults), opts or {})
  for _, option in ipairs({
    { config, "notify" },
    { config.progress, "enabled" },
    { config.lsp, "enabled" },
  }) do
    assert(type(option[1][option[2]]) == "boolean", option[2] .. " must be a boolean")
  end
  for _, path in ipairs({
    { config, "timeout", 0 },
    { config, "history_size", 0 },
    { config, "max_notifications", 1 },
    { config, "max_pending", 1 },
    { config.window, "max_width", 1 },
    { config.window, "min_width", 1 },
    { config.window, "max_height", 1 },
    { config.window, "top", 0 },
    { config.window, "right", 0 },
    { config.window, "bottom", 0 },
    { config.window, "winblend", 0 },
    { config.window, "zindex", 1 },
    { config.progress, "max_items", 1 },
    { config.progress, "interval", 16 },
    { config.progress, "done_ttl", 0 },
    { config.progress, "stale_timeout", 0 },
  }) do
    local value = path[1][path[2]]
    assert(
      type(value) == "number"
        and value >= path[3]
        and value < math.huge
        and value == math.floor(value),
      path[2] .. " must be an integer >= " .. path[3]
    )
  end
  assert(config.window.winblend <= 100, "winblend must be <= 100")
  -- Replace lists rather than recursively merging default array elements.
  if opts and opts.progress then
    config.progress.avoid = vim.deepcopy(opts.progress.avoid or config.progress.avoid)
    config.progress.spinner = vim.deepcopy(opts.progress.spinner or config.progress.spinner)
  end
  for _, list in ipairs({ config.progress.avoid, config.lsp.ignore }) do
    assert(vim.islist(list), "avoid and ignore must be lists")
    for _, item in ipairs(list) do
      assert(type(item) == "string", "avoid and ignore entries must be strings")
    end
  end
  assert(
    vim.islist(config.progress.spinner) and #config.progress.spinner > 0,
    "spinner cannot be empty"
  )
  for _, frame in ipairs(config.progress.spinner) do
    assert(type(frame) == "string" and frame ~= "", "spinner frames must be nonempty strings")
  end
  assert(
    vim.tbl_contains({ "rounded", "single", "double", "solid", "none", "" }, config.window.border),
    "unsupported border"
  )
  config.level = M.level(config.level)
  return config
end

return M
