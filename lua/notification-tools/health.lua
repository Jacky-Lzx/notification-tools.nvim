local M = {}

function M.check()
  vim.health.start("notification-tools.nvim")
  if vim.fn.has("nvim-0.10") == 1 then
    vim.health.ok("Neovim >= 0.10")
  else
    vim.health.error("Neovim >= 0.10 is required")
  end
  if #vim.api.nvim_list_uis() == 0 then
    vim.health.info("No UI attached; floating windows need a TUI or GUI to be visible")
  end
  if package.loaded["fidget"] then
    vim.health.warn("Fidget is loaded; disable its progress UI to avoid duplicate status displays")
  end
  if package.loaded["snacks.notifier"] then
    vim.health.warn("Snacks notifier is loaded; disable it when notification-tools owns vim.notify")
  end
  vim.health.info("Keep Noice notify.enabled=false and lsp.progress.enabled=false")
end

return M
