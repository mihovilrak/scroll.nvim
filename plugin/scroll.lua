-- Load guard, user commands and the automatic setup. Nothing is required until
-- startup has finished, so the plugin costs nothing while Nvim starts.
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

vim.api.nvim_create_user_command("ScrollMinimapToggle", function()
  require("scroll").toggle_minimap()
end, { desc = "Toggle the scroll.nvim minimap" })

-- Work without a `setup()` call. Deferred until startup is over (or, when
-- lazy-loaded later, to the next event-loop turn) so that a user's own
-- `setup(opts)` in their config, or a plugin manager's, runs first and wins.
local function auto_setup()
  local scroll = require("scroll")
  if not scroll.did_setup then
    scroll.setup()
  end
end

if vim.v.vim_did_enter == 1 then
  vim.schedule(auto_setup)
else
  vim.api.nvim_create_autocmd("VimEnter", { once = true, callback = auto_setup })
end
