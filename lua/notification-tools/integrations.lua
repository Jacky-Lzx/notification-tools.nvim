local M = {}
local lsp = {}

function M.reset()
  lsp = {}
end

function M.prune()
  for id, tasks in pairs(lsp) do
    for token, handle in pairs(tasks) do
      if not handle:is_active() then
        tasks[token] = nil
      end
    end
    if not next(tasks) then
      lsp[id] = nil
    end
  end
end

function M.setup(tools, config, group)
  M.reset()
  if config.lsp.enabled then
    vim.api.nvim_create_autocmd("LspProgress", {
      group = group,
      callback = function(event)
        M.prune()
        local data = event.data or {}
        local params = data.params or {}
        local value = params.value
        if
          type(value) ~= "table" or not vim.tbl_contains({ "begin", "report", "end" }, value.kind)
        then
          return
        end
        local client = vim.lsp.get_client_by_id(data.client_id)
        if not client or vim.tbl_contains(config.lsp.ignore, client.name) then
          return
        end
        local token = params.token
        if type(token) ~= "string" and type(token) ~= "number" then
          return
        end
        lsp[data.client_id] = lsp[data.client_id] or {}
        local tasks = lsp[data.client_id]
        local handle = tasks[token]
        if value.kind == "begin" and handle then
          handle:cancel("Replaced")
          handle = nil
        end
        if value.kind == "begin" or (not handle and value.kind == "report") then
          -- Include token type: numeric 1 and string "1" are different LSP tokens.
          local id = "lsp:" .. data.client_id .. ":" .. type(token) .. ":" .. token
          handle =
            tools.progress({ id = id, title = value.title or "Working", source = client.name })
          tasks[token] = handle
        end
        if handle then
          handle:update({
            title = value.title,
            message = value.message,
            percentage = value.percentage,
          })
          if value.kind == "end" then
            handle:finish(value.message)
            tasks[token] = nil
          end
        end
        if not next(tasks) then
          lsp[data.client_id] = nil
        end
      end,
    })
    vim.api.nvim_create_autocmd("LspDetach", {
      group = group,
      callback = function(event)
        local id = event.data and event.data.client_id
        if not id then
          return
        end
        local current = lsp
        -- A client can be attached to several buffers. A single detach is not an exit.
        vim.schedule(function()
          if current ~= lsp then
            return
          end
          local client = id and vim.lsp.get_client_by_id(id)
          if client and not client:is_stopped() and next(client.attached_buffers or {}) then
            return
          end
          for _, handle in pairs(lsp[id] or {}) do
            handle:cancel("Client stopped")
          end
          lsp[id] = nil
        end)
      end,
    })
  end
end

return M
