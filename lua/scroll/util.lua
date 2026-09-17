local config = require("scroll.config")

local M = {}

--- A floating window has a non-empty `relative`. We never decorate floats --
--- including, crucially, our own bars, which is what keeps refreshes from
--- feeding back into themselves. The one exception is the Snacks explorer's
--- list, see `kind`.
--- @param win integer
--- @return boolean
function M.is_float(win)
  local ok, cfg = pcall(vim.api.nvim_win_get_config, win)
  return ok and cfg.relative ~= nil and cfg.relative ~= ""
end

--- What kind of bars `win` carries, or nil for none:
---   "code"      an ordinary window: both bars, marks and the minimap
---   "explorer"  a file-tree sidebar (neo-tree, nvim-tree): vertical bar only
---   "snacks"    the Snacks explorer's list float: vertical bar only, measured
---               from the picker rather than the window
--- @param win integer
--- @return "code"|"explorer"|"snacks"|nil
function M.kind(win)
  if not vim.api.nvim_win_is_valid(win) then
    return nil
  end
  local opts = config.options
  if M.is_float(win) then
    return require("scroll.explorer").list_of(win) and "snacks" or nil
  end

  local buf = vim.api.nvim_win_get_buf(win)
  if not vim.api.nvim_buf_is_valid(buf) then
    return nil
  end

  local width = vim.api.nvim_win_get_width(win)
  local height = vim.api.nvim_win_get_height(win)
  local filetype = vim.bo[buf].filetype

  local explorer = opts.explorer
  if explorer.enabled and vim.tbl_contains(explorer.filetypes, filetype) then
    return (width >= explorer.min_width and height >= opts.min_height) and "explorer" or nil
  end

  if vim.tbl_contains(opts.excluded_buftypes, vim.bo[buf].buftype) then
    return nil
  end
  if vim.tbl_contains(opts.excluded_filetypes, filetype) then
    return nil
  end

  -- The cmdline window ignores most window manipulation; leave it alone.
  if vim.fn.win_gettype(win) == "command" then
    return nil
  end

  return (width >= opts.min_width and height >= opts.min_height) and "code" or nil
end

--- @param win integer
--- @return boolean  whether this window should carry scrollbars at all
function M.is_eligible(win)
  return M.kind(win) ~= nil
end

--- Whether the minimap belongs over `win`: only ordinary file buffers, not
--- terminals, dashboards or scratch views, which are not code.
--- @param win integer
--- @return boolean
function M.minimap_eligible(win)
  if M.kind(win) ~= "code" then
    return false
  end
  local mm = config.options.minimap
  local buf = vim.api.nvim_win_get_buf(win)
  if mm.enabled_for then
    local ok, verdict = pcall(mm.enabled_for, buf, win)
    if ok and verdict ~= nil then
      return verdict and true or false
    end
  end
  return vim.bo[buf].buftype == "" and not vim.tbl_contains(mm.excluded_filetypes, vim.bo[buf].filetype)
end

--- Every window in the current tabpage that carries bars.
--- @return integer[]
function M.target_windows()
  return vim.tbl_filter(M.is_eligible, vim.api.nvim_tabpage_list_wins(0))
end

--- 'scrolloff'/'sidescrolloff' as they apply to `win`, as the margins Nvim
--- actually keeps before and after the cursor across `span` cells. A value too
--- large to honour (the "keep centred" idiom) centres the cursor, and Nvim
--- centres at row `(span - 1) / 2` but at column `span / 2`, so the caller says
--- which cap applies.
--- @param win integer
--- @param name "scrolloff"|"sidescrolloff"
--- @param span integer
--- @param center integer
--- @return integer before, integer after
function M.margins(win, name, span, center)
  local value = vim.wo[win][name]
  if value < 0 then
    value = vim.o[name]
  end
  local before = math.max(0, math.min(value, center))
  local after = math.max(0, math.min(value, span - 1 - before))
  return before, after
end

return M
