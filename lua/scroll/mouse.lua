--- Click-to-jump, thumb dragging and hover.
---
--- Hit testing has to cope with an ambiguity: depending on the build and on
--- whether the float is focusable, `getmousepos()` over a bar reports either
--- the bar's own float or the window underneath it. Probing headless gave
--- contradictory answers, so `locate` handles both -- it maps a float back to
--- its parent when it sees one, and otherwise uses the reported window
--- directly. Either way it ends up with a parent window and a cell offset.
local config = require("scroll.config")
local geometry = require("scroll.geometry")
local measure = require("scroll.measure")
local render = require("scroll.render")

local M = {}

--- Mappings we replaced, so a click that misses the bars still does whatever
--- it did before this plugin loaded.
--- @type table<string, table|false>
local previous = {}

--- @type { win: integer, orientation: string, grab: integer }|nil
local drag = nil

local function capture(mode, lhs)
  local existing = vim.fn.maparg(lhs, mode, false, true)
  previous[mode .. lhs] = (existing and next(existing)) and existing or false
end

--- Replay whatever the key did before we took it over.
local function fallthrough(mode, lhs)
  local prev = previous[mode .. lhs]
  if prev and prev.callback then
    prev.callback()
  elseif prev and prev.rhs and prev.rhs ~= "" then
    vim.api.nvim_feedkeys(vim.keycode(prev.rhs), prev.noremap == 1 and "n" or "m", false)
  else
    -- No prior mapping: replay the builtin. "n" means the keys are not
    -- remapped, so this does not re-enter our own mapping. Neovim carries the
    -- pointer position separately from the keycode, so the click lands where
    -- the user actually clicked.
    vim.api.nvim_feedkeys(vim.keycode(lhs), "n", false)
  end
end

--- Resolve the pointer to a window, and to a cell offset within that window's
--- text area.
--- @return table|nil `{ win, row, col, info }` with 0-based row/col
local function locate()
  local pos = vim.fn.getmousepos()
  if pos.winid == 0 then
    return nil
  end

  local win = pos.winid
  local owner = render.owner_of(win)
  if owner then
    -- The pointer resolved to one of our own floats; the window it decorates
    -- is the one we actually care about.
    win = owner
  end

  if not vim.api.nvim_win_is_valid(win) then
    return nil
  end
  local info = vim.fn.getwininfo(win)[1]
  if not info then
    return nil
  end

  -- `winrow`/`wincol` are 1-based and include the winbar and the gutter, but
  -- they are only meaningful when the pointer resolved to the parent window.
  -- Screen coordinates are always valid, so derive from those instead.
  local row = pos.screenrow - info.winrow - info.winbar
  local col = pos.screencol - info.wincol

  return { win = win, row = row, col = col, info = info }
end

--- Which bar, if any, sits under the pointer.
--- @return string|nil orientation, table|nil hit
local function hit_test()
  local at = locate()
  if not at then
    return nil, nil
  end

  local opts = config.options
  local info = at.info
  if at.row < 0 or at.row >= info.height then
    return nil, nil -- winbar, statusline, or outside the window
  end

  local computed = render.compute(at.win)

  if computed.vertical and at.col >= info.width - opts.vertical.width then
    return "vertical", at
  end

  local h = computed.horizontal
  if h and at.row >= info.height - opts.horizontal.height then
    local c = at.col - h.textoff
    if c >= 0 and c < h.track then
      return "horizontal", at
    end
  end

  return nil, nil
end

--- Scroll `win` so the thumb's leading edge sits at `track_pos`.
local function scroll_to(win, orientation, track_pos, grab)
  local computed = render.compute(win)
  local info = computed.info
  if not info then
    return
  end

  if orientation == "vertical" then
    local v = computed.vertical
    if not v then
      return
    end
    local target = geometry.offset_at({
      track = info.height,
      total = v.total,
      page = v.page,
      pos = track_pos - grab,
    })
    local topline = measure.topline_at(win, target)
    vim.api.nvim_win_call(win, function()
      vim.fn.winrestview({ topline = topline })
    end)
  else
    local h = computed.horizontal
    if not h then
      return
    end
    local leftcol = geometry.offset_at({
      track = h.track,
      total = h.total,
      page = h.page,
      pos = track_pos - grab,
    })
    vim.api.nvim_win_call(win, function()
      vim.fn.winrestview({ leftcol = leftcol })
    end)
  end

  -- A mapping does not repaint until it returns, which would make a drag feel
  -- like it lags a frame behind the pointer.
  pcall(vim.api.nvim__redraw, { win = win, valid = true, flush = true })
end

--- Where along its track the thumb currently starts.
local function thumb_start(win, orientation)
  local computed = render.compute(win)
  if orientation == "vertical" then
    return computed.vertical and computed.vertical.pos or 0, computed.vertical and computed.vertical.size or 1
  end
  return computed.horizontal and computed.horizontal.pos or 0, computed.horizontal and computed.horizontal.size or 1
end

local function track_position(at, orientation, info)
  if orientation == "vertical" then
    return at.row
  end
  local computed = render.compute(at.win)
  local textoff = computed.horizontal and computed.horizontal.textoff or info.textoff
  return at.col - textoff
end

local function on_press()
  local orientation, at = hit_test()
  if not orientation then
    drag = nil
    return false
  end

  local pos = track_position(at, orientation, at.info)
  local start, size = thumb_start(at.win, orientation)

  -- Grabbing the thumb keeps the point you grabbed under the pointer; clicking
  -- the bare track centres the thumb on the click, as VS Code does.
  local grab = (pos >= start and pos < start + size) and (pos - start) or math.floor(size / 2)

  drag = { win = at.win, orientation = orientation, grab = grab }
  scroll_to(at.win, orientation, pos, grab)
  return true
end

local function on_drag()
  if not drag or not vim.api.nvim_win_is_valid(drag.win) then
    return false
  end

  -- During a drag the pointer routinely leaves the bar, so this deliberately
  -- does not hit-test; it keeps steering the window the drag started on.
  local pos = vim.fn.getmousepos()
  local info = vim.fn.getwininfo(drag.win)[1]
  if not info then
    return false
  end

  local track_pos
  if drag.orientation == "vertical" then
    track_pos = pos.screenrow - info.winrow - info.winbar
    track_pos = math.max(0, math.min(track_pos, info.height - 1))
  else
    local computed = render.compute(drag.win)
    local h = computed.horizontal
    if not h then
      return false
    end
    track_pos = pos.screencol - info.wincol - h.textoff
    track_pos = math.max(0, math.min(track_pos, h.track - 1))
  end

  scroll_to(drag.win, drag.orientation, track_pos, drag.grab)
  return true
end

local function on_release()
  if drag then
    drag = nil
    return true
  end
  return false
end

local function on_move()
  local orientation, at = hit_test()
  local changed = (render.hover.win ~= (at and at.win)) or (render.hover.orientation ~= orientation)
  render.hover = { win = at and at.win or nil, orientation = orientation }
  if changed then
    require("scroll.visibility").on_activity()
  end
  return false -- always fall through; other plugins listen for <MouseMove>
end

local MODES = { "n", "v", "s", "o", "i" }

local handlers = {
  ["<LeftMouse>"] = on_press,
  ["<LeftDrag>"] = on_drag,
  ["<LeftRelease>"] = on_release,
}

function M.enable()
  for lhs, handler in pairs(handlers) do
    for _, mode in ipairs(MODES) do
      capture(mode, lhs)
      vim.keymap.set(mode, lhs, function()
        local ok, consumed = pcall(handler)
        if ok and consumed then
          return
        end
        fallthrough(mode, lhs)
      end, { silent = true, desc = "scroll.nvim: " .. lhs })
    end
  end

  if config.options.visibility == "hover" and vim.o.mousemoveevent then
    for _, mode in ipairs({ "n", "v", "i" }) do
      capture(mode, "<MouseMove>")
      vim.keymap.set(mode, "<MouseMove>", function()
        pcall(on_move)
        fallthrough(mode, "<MouseMove>")
      end, { silent = true, desc = "scroll.nvim: hover" })
    end
  end
end

function M.disable()
  drag = nil
  for key in pairs(previous) do
    local mode, lhs = key:sub(1, 1), key:sub(2)
    pcall(vim.keymap.del, mode, lhs)
  end
  previous = {}
end

return M
