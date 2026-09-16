local config = require("scroll.config")

local M = {}

--- A floating window has a non-empty `relative`. We never decorate floats --
--- including, crucially, our own bars, which is what keeps refreshes from
--- feeding back into themselves.
--- @param win integer
--- @return boolean
function M.is_float(win)
  local ok, cfg = pcall(vim.api.nvim_win_get_config, win)
  return ok and cfg.relative ~= nil and cfg.relative ~= ""
end

--- @param win integer
--- @return boolean  whether this window should carry scrollbars at all
function M.is_eligible(win)
  if not vim.api.nvim_win_is_valid(win) or M.is_float(win) then
    return false
  end

  local opts = config.options
  local buf = vim.api.nvim_win_get_buf(win)
  if not vim.api.nvim_buf_is_valid(buf) then
    return false
  end

  if vim.tbl_contains(opts.excluded_buftypes, vim.bo[buf].buftype) then
    return false
  end
  if vim.tbl_contains(opts.excluded_filetypes, vim.bo[buf].filetype) then
    return false
  end

  -- The cmdline window ignores most window manipulation; leave it alone.
  if vim.fn.win_gettype(win) == "command" then
    return false
  end

  local width = vim.api.nvim_win_get_width(win)
  local height = vim.api.nvim_win_get_height(win)
  return width >= opts.min_width and height >= opts.min_height
end

--- Every ordinary window in the current tabpage.
--- @return integer[]
function M.target_windows()
  return vim.tbl_filter(M.is_eligible, vim.api.nvim_tabpage_list_wins(0))
end

return M
