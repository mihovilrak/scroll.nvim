--- Autocmd wiring and the refresh coalescer.
local highlight = require("scroll.highlight")
local measure = require("scroll.measure")
local render = require("scroll.render")
local visibility = require("scroll.visibility")
local width = require("scroll.width")

local M = {}

local group = nil
local pending = false

--- Re-entrancy guard. Creating, moving and closing our own floats can emit
--- window events; without this they would schedule another refresh, which
--- would touch the floats again, and so on.
local suspended = 0

function M.suspend()
  suspended = suspended + 1
end

function M.resume()
  suspended = math.max(0, suspended - 1)
end

--- Ask for a refresh. Many events in one event-loop turn collapse into exactly
--- one redraw.
---
--- `vim.schedule` rather than a debounce timer is deliberate: a single
--- keystroke can fire TextChangedI, CursorMovedI and WinScrolled together, and
--- this already collapses them into one pass with no added latency. A
--- millisecond debounce would only make scrolling feel behind the text.
function M.schedule()
  if pending or suspended > 0 then
    return
  end
  pending = true
  vim.schedule(function()
    pending = false
    if suspended > 0 then
      return
    end
    M.suspend()
    local ok, err = pcall(visibility.on_activity)
    M.resume()
    if not ok then
      vim.notify("scroll.nvim: " .. tostring(err), vim.log.levels.ERROR)
    end
  end)
end

local function au(event, opts)
  opts = opts or {}
  vim.api.nvim_create_autocmd(event, {
    group = group,
    pattern = opts.pattern,
    callback = function(args)
      if suspended > 0 then
        return
      end
      if opts.handler then
        opts.handler(args)
      end
      if opts.refresh ~= false then
        M.schedule()
      end
    end,
  })
end

function M.enable()
  group = vim.api.nvim_create_augroup("scroll.nvim", { clear = true })

  -- Viewport moved or changed shape.
  au({ "WinScrolled", "WinResized", "VimResized", "WinEnter", "BufWinEnter", "TabEnter", "TabNewEntered" })

  -- Content changed. Width invalidation rides on changedtick inside width.lua.
  au({ "TextChanged", "TextChangedI", "TextChangedP" })

  -- Folds can open or close without any dedicated event, and the cursor
  -- moving is the usual way that happens.
  au({ "CursorMoved", "CursorMovedI" })

  -- Anything that changes the gutter width, the wrap mode, or the rendered
  -- height invalidates the cached measurements.
  au("OptionSet", {
    pattern = "wrap,number,relativenumber,signcolumn,foldcolumn,statuscolumn,list,"
      .. "tabstop,breakindent,diff,foldlevel,foldenable,foldmethod,winbar,cmdheight,laststatus",
    handler = function()
      measure.reset()
    end,
  })

  au("ColorScheme", {
    handler = function()
      highlight.setup()
    end,
  })

  -- `nvim_open_win` is not allowed while the command-line window is open.
  au("CmdwinEnter", {
    handler = function()
      M.suspend()
      render.hide_all()
    end,
    refresh = false,
  })
  au("CmdwinLeave", {
    handler = function()
      M.resume()
    end,
  })

  au("WinClosed", {
    handler = function(args)
      local win = tonumber(args.match)
      if win then
        render.clear(win)
      end
    end,
  })

  au({ "BufDelete", "BufWipeout" }, {
    handler = function(args)
      width.forget(args.buf)
    end,
    refresh = false,
  })

  -- Window IDs are all new after a session restore, so start over.
  au("SessionLoadPost", {
    handler = function()
      render.clear_all()
      measure.reset()
    end,
  })

  -- Cheap idle self-healing: reap bars whose window vanished without a
  -- WinClosed we saw (it can be missed during `:qa`).
  au("SafeState", {
    handler = function()
      render.prune()
    end,
    refresh = false,
  })

  vim.api.nvim_create_autocmd("VimLeavePre", {
    group = group,
    callback = function()
      M.disable()
    end,
  })
end

function M.disable()
  if group then
    pcall(vim.api.nvim_del_augroup_by_id, group)
    group = nil
  end
  pending = false
  suspended = 0
  visibility.stop()
  render.clear_all()
  measure.reset()
  width.reset()
end

return M
