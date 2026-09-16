-- Load guard and user commands only. Nothing is required here, so the plugin
-- costs nothing at startup until `require("scroll").setup()` runs.
if vim.g.loaded_scroll then
  return
end
vim.g.loaded_scroll = true

vim.api.nvim_create_user_command("ScrollToggle", function()
  require("scroll").toggle()
end, { desc = "Toggle scroll.nvim scrollbars" })

vim.api.nvim_create_user_command("ScrollEnable", function()
  require("scroll").enable()
end, { desc = "Enable scroll.nvim scrollbars" })

vim.api.nvim_create_user_command("ScrollDisable", function()
  require("scroll").disable()
end, { desc = "Disable scroll.nvim scrollbars" })

vim.api.nvim_create_user_command("ScrollRefresh", function()
  require("scroll").refresh()
end, { desc = "Redraw scroll.nvim scrollbars now" })
