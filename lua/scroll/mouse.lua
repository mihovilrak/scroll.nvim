--- Click-to-jump, thumb dragging and hover.
---
--- Over a bar, `getmousepos()` may report either the bar's float or the
--- window underneath it, so `locate` accepts both and resolves to the parent
--- window and a cell offset.
local config = require("scroll.config")
local explorer = require("scroll.explorer")
local geometry = require("scroll.geometry")
local measure = require("scroll.measure")
local minimap = require("scroll.minimap")
local render = require("scroll.render")
local util = require("scroll.util")

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

  local map = computed.minimap
  if map and render.minimap_shown(at.win) and at.col >= map.col and at.col < map.col + map.width then
    return "minimap", at
  end

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

local margins = util.margins

--- Set `topline`, moving the cursor into the new view when it would fall
--- outside. Nvim keeps the cursor on screen, so a view the cursor is not in is
--- scrolled straight back on the next redraw.
local function set_topline(win, topline)
  vim.api.nvim_win_call(win, function()
    local height = vim.fn.getwininfo(win)[1].height
    local above, below = margins(win, "scrolloff", height, math.floor((height - 1) / 2))
    local lnum = vim.fn.line(".")
    local top = math.min(topline + above, vim.fn.line("$"))
    if lnum < top then
      vim.fn.winrestview({ topline = topline, lnum = top })
      return
    end
    -- With wrapping, `height` lines may not fit; place the cursor first,
    -- then let Nvim say where the view ends.
    vim.fn.winrestview({ topline = topline, lnum = top })
    local bottom = math.max(top, vim.fn.line("w$") - below)
    vim.fn.winrestview({ topline = topline, lnum = math.min(lnum, bottom) })
  end)
end

--- Set `leftcol`, moving the cursor into the new view when it would fall
--- outside. If the cursor line is too short to reach the view at all, the
--- cursor moves to the nearest visible line that is long enough.
local function set_leftcol(win, leftcol)
  vim.api.nvim_win_call(win, function()
    local info = vim.fn.getwininfo(win)[1]
    local textw = info.width - info.textoff
    local left, right = margins(win, "sidescrolloff", textw, math.floor(textw / 2))
    local lo, hi = leftcol + left + 1, leftcol + textw - right -- 1-based virtual columns

    local function reaches(l)
      return leftcol == 0 or vim.fn.virtcol({ l, "$" }) - 1 >= lo
    end

    local lnum = vim.fn.line(".")
    if not reaches(lnum) then
      local found = nil
      for d = 1, info.botline - info.topline do
        for _, l in ipairs({ lnum - d, lnum + d }) do
          if not found and l >= info.topline and l <= info.botline and reaches(l) then
            found = l
          end
        end
        if found then
          break
        end
      end
      if not found then
        vim.fn.winrestview({ leftcol = leftcol })
        return
      end
      lnum = found
    end

    local vcol = lnum == vim.fn.line(".") and vim.fn.virtcol(".") or lo
    local target = math.max(lo, math.min(vcol, hi))
    local col = math.max(0, vim.fn.virtcol2col(0, lnum, target) - 1)
    vim.fn.winrestview({ lnum = lnum, leftcol = leftcol, col = col, curswant = target - 1 })
  end)
end

--- Centre `win` on the buffer line under minimap row `row`.
local function minimap_jump(win, row)
  local computed = render.compute(win)
  local map, info = computed.minimap, computed.info
  if not map then
    return
  end
  local buf = vim.api.nvim_win_get_buf(win)
  local line = math.min(minimap.line_at(map, row), vim.api.nvim_buf_line_count(buf))
  local page = info.botline - info.topline + 1
  set_topline(win, math.max(1, line - math.floor(page / 2)))
  pcall(vim.api.nvim__redraw, { win = win, valid = true, flush = true })
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
    if computed.kind == "snacks" then
      -- Rewriting the list fires nothing `WinScrolled` would catch, unlike
      -- `set_topline` below, so the thumb would otherwise sit still until the
      -- next idle `SafeState` poll notices and redraws it.
      explorer.scroll_to(win, target + 1)
      render.refresh(win)
    else
      set_topline(win, measure.topline_at(win, target))
    end
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
    set_leftcol(win, leftcol)
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
  -- A release that never reached us must not leave an old drag steering.
  drag = nil
  local orientation, at = hit_test()
  if not orientation then
    drag = nil
    return false
  end

  if orientation == "minimap" then
    drag = { win = at.win, orientation = orientation, grab = 0 }
    minimap_jump(at.win, at.row)
    return true
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
  if drag.orientation == "minimap" then
    local row = pos.screenrow - info.winrow - info.winbar
    minimap_jump(drag.win, math.max(0, math.min(row, info.height - 1)))
    return true
  elseif drag.orientation == "vertical" then
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

--- Lines and columns one wheel step scrolls, from 'mousescroll'.
--- @return integer ver, integer hor
local function wheel_step()
  local ver, hor = 3, 6
  for part in vim.gsplit(vim.o.mousescroll, ",", { plain = true }) do
    local key, n = part:match("^(%a+):(%d+)$")
    if key == "ver" then
      ver = tonumber(n)
    elseif key == "hor" then
      hor = tonumber(n)
    end
  end
  return ver, hor
end

--- A wheel event over a bar scrolls the window the bar belongs to. Left to
--- Nvim, it would scroll the bar's own float, whose rows would then no longer
--- line up with the window.
--- @param dir "up"|"down"|"left"|"right"
local function on_wheel(dir)
  local orientation, at = hit_test()
  if not orientation then
    return false
  end
  local win, info = at.win, at.info
  local ver, hor = wheel_step()
  local computed = render.compute(win)
  if dir == "up" or dir == "down" then
    local delta = dir == "down" and ver or -ver
    if computed.kind == "snacks" then
      explorer.scroll_by(win, delta)
      render.refresh(win)
    else
      local buf = vim.api.nvim_win_get_buf(win)
      local last = math.max(1, vim.api.nvim_buf_line_count(buf) - (info.botline - info.topline))
      set_topline(win, math.max(1, math.min(info.topline + delta, last)))
    end
  else
    local h = computed.horizontal
    if not h then
      return true -- nothing to scroll sideways, but the float must not move
    end
    local delta = dir == "right" and hor or -hor
    set_leftcol(win, math.max(0, math.min(info.leftcol + delta, h.total - h.page)))
  end
  pcall(vim.api.nvim__redraw, { win = win, valid = true, flush = true })
  return true
end

--- The Snacks explorer's list intercepts the wheel at the `vim.on_key` level
--- (`snacks/picker/core/list.lua`), before Nvim's mapping layer, and on
--- 0.11+ swallows it outright (returns `""`) to stop the window scrolling
--- natively too. That means `<ScrollWheelUp>`/`<ScrollWheelDown>` below never
--- fires for a wheel scroll over the list itself, which is the common case
--- since the bar is only the thin strip at the window's edge. Without this,
--- the thumb would sit stale until the next idle `SafeState` poll notices.
--- This watches the same way Snacks does and nudges our own poll once
--- Snacks' own (also deferred) scroll has had a chance to run.
local SCROLL_WHEEL_UP = vim.api.nvim_replace_termcodes("<ScrollWheelUp>", true, true, true)
local SCROLL_WHEEL_DOWN = vim.api.nvim_replace_termcodes("<ScrollWheelDown>", true, true, true)
local wheel_watch_ns = vim.api.nvim_create_namespace("scroll.nvim.wheel_watch")

local function watch_wheel(key, typed)
  key = typed or key
  if key ~= SCROLL_WHEEL_UP and key ~= SCROLL_WHEEL_DOWN then
    return
  end
  local win = vim.fn.getmousepos().winid
  if win ~= 0 and util.kind(win) == "snacks" then
    -- A timer callback, not another `vim.schedule`, so this reliably runs
    -- after Snacks' own `vim.schedule`-deferred `list:scroll` regardless of
    -- which `vim.on_key` listener ran first.
    vim.defer_fn(function()
      require("scroll.events").schedule()
    end, 0)
  end
end

local MODES = { "n", "v", "s", "o", "i" }

local handlers = {
  ["<LeftMouse>"] = on_press,
  ["<LeftDrag>"] = on_drag,
  ["<LeftRelease>"] = on_release,
  ["<ScrollWheelUp>"] = function()
    return on_wheel("up")
  end,
  ["<ScrollWheelDown>"] = function()
    return on_wheel("down")
  end,
  ["<ScrollWheelLeft>"] = function()
    return on_wheel("left")
  end,
  ["<ScrollWheelRight>"] = function()
    return on_wheel("right")
  end,
}

function M.enable()
  vim.on_key(watch_wheel, wheel_watch_ns)

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
  vim.on_key(nil, wheel_watch_ns)
  drag = nil
  for key in pairs(previous) do
    local mode, lhs = key:sub(1, 1), key:sub(2)
    pcall(vim.keymap.del, mode, lhs)
  end
  previous = {}
end

-- Exposed for tests: exercising these through real mouse events needs a UI.
M._set_topline = set_topline
M._set_leftcol = set_leftcol
M._minimap_jump = minimap_jump
M._watch_wheel = watch_wheel
M._scroll_to = scroll_to

return M
