-- Local development spec. Load before producers that call vim.notify.
return {
  {
    dir = vim.fn.expand("~/Documents/Github/nvim_plugins/notification-tools.nvim"),
    name = "notification-tools.nvim",
    main = "notification-tools",
    lazy = false,
    priority = 1100,
    opts = {
      window = { border = "rounded", winblend = 0 },
      notification = { window = { padding = { horizontal = 2, vertical = 0 } } },
      progress = {
        window = { border = "rounded", max_width = 44 },
        avoid = { "NvimTree", "TestExplorer" },
      },
    },
    keys = {
      { "<leader>sn", "<Cmd>Notifications<CR>", desc = "[Notifications] History" },
      { "<leader>n", "<Cmd>Notifications<CR>", desc = "[Notifications] History" },
      { "<leader>un", "<Cmd>NotificationsDismiss<CR>", desc = "[Notifications] Dismiss" },
    },
  },
}
