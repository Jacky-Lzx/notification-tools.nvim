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
    gap = 1,
    padding = { horizontal = 1, vertical = 0 },
  },
  notification = {
    dnd = false,
    dnd_level = vim.log.levels.ERROR,
    -- filter(notice) -> "show" (or nil), "history", "drop"
    markdown = true,
    merge_duplicates = true,
    timestamp = true,
    fade_out = 180,
    window = { padding = { horizontal = 2, vertical = 0 } },
  },
  progress = {
    enabled = true,
    style = "bar",
    max_items = 6,
    done_ttl = 1500,
    history = "errors",
    stale_timeout = 120000,
    interval = 80,
    group_by_source = true,
    show_elapsed = true,
    fade_out = 240,
    window = { min_width = 24, max_width = 44, max_height = 12 },
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

function M.task_history(value)
  assert(
    value == false or value == "errors" or value == "all",
    "progress history must be false, errors or all"
  )
  return value
end

function M.resolve(opts)
  local config = vim.tbl_deep_extend("force", vim.deepcopy(M.defaults), opts or {})
  for _, section in ipairs({ "notification", "progress" }) do
    config[section].window = vim.tbl_deep_extend("force", config.window, config[section].window)
  end
  for _, option in ipairs({
    { config, "notify" },
    { config.progress, "enabled" },
    { config.lsp, "enabled" },
    { config.notification, "merge_duplicates" },
    { config.notification, "markdown" },
    { config.notification, "timestamp" },
    { config.notification, "dnd" },
    { config.progress, "group_by_source" },
    { config.progress, "show_elapsed" },
  }) do
    assert(type(option[1][option[2]]) == "boolean", option[2] .. " must be a boolean")
  end
  for _, path in ipairs({
    { config, "timeout", 0 },
    { config, "history_size", 0 },
    { config, "max_notifications", 1 },
    { config, "max_pending", 1 },
    { config.progress, "max_items", 1 },
    { config.progress, "interval", 16 },
    { config.progress, "done_ttl", 0 },
    { config.progress, "stale_timeout", 0 },
    { config.notification, "fade_out", 0 },
    { config.progress, "fade_out", 0 },
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
  for _, window in ipairs({ config.window, config.notification.window, config.progress.window }) do
    for key, minimum in pairs({
      min_width = 1,
      max_width = 1,
      max_height = 1,
      top = 0,
      right = 0,
      bottom = 0,
      zindex = 1,
      winblend = 0,
      gap = 0,
    }) do
      local value = window[key]
      assert(
        type(value) == "number"
          and value >= minimum
          and value < math.huge
          and value == math.floor(value),
        key .. " must be a finite integer >= " .. minimum
      )
    end
    assert(window.winblend <= 100, "winblend must be <= 100")
    assert(
      vim.tbl_contains({ "rounded", "single", "double", "solid", "none", "" }, window.border),
      "unsupported border"
    )
    for _, axis in ipairs({ "horizontal", "vertical" }) do
      local value = window.padding[axis]
      assert(
        type(value) == "number" and value >= 0 and value < math.huge and value == math.floor(value),
        "padding must contain finite nonnegative integers"
      )
    end
  end
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
    config.notification.filter == nil or type(config.notification.filter) == "function",
    "notification.filter must be a function"
  )
  config.notification.dnd_level = M.level(config.notification.dnd_level)
  assert(
    vim.tbl_contains({ "bar", "compact" }, config.progress.style),
    "progress.style must be bar or compact"
  )
  config.progress.history = M.task_history(config.progress.history)
  config.level = M.level(config.level)
  return config
end

return M
