-- Run with: nvim --headless -u NONE -l tests/minimap_spec.lua
package.path = "lua/?.lua;lua/?/init.lua;" .. package.path
local t = dofile("tests/harness.lua")

-- The screen is left at the headless default of 80x24. Resizing it and then
-- splitting windows crashes headless Nvim itself (0.11.6 aborts with a double
-- free; nightly fails an assertion in grid.c), with or without this plugin.
vim.o.laststatus, vim.o.swapfile = 2, false

dofile("plugin/scroll.lua")
local scroll = require("scroll")
local config = require("scroll.config")
local minimap = require("scroll.minimap")
local mouse = require("scroll.mouse")
local render = require("scroll.render")

local function fill(n, text)
  local lines = {}
  for i = 1, n do
    lines[i] = (text or "line ") .. i
  end
  local buf = vim.api.nvim_create_buf(true, false)
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
  vim.api.nvim_win_set_buf(vim.api.nvim_get_current_win(), buf)
  return buf, vim.api.nvim_get_current_win()
end

local function float_of(win, key)
  for _, w in ipairs(vim.api.nvim_tabpage_list_wins(0)) do
    local parent, which = render.owner_of(w)
    if parent == win and which == key then
      return w
    end
  end
end

local function braille(bits)
  return vim.fn.nr2char(0x2800 + bits)
end

-- Width and dot size are pinned so the expectations below do not follow the defaults.
scroll.setup({
  visibility = "always",
  mouse = false,
  minimap = { enabled = true, min_window_width = 50, width = 20, columns_per_dot = 2 },
})

t.describe("encode: dots follow the text", function()
  t.eq(minimap.encode({ "ab" }, 1, 1, 8), braille(0x01 + 0x08), "two chars light the top row of one cell")
  t.eq(minimap.encode({ "a", "a", "a", "a" }, 1, 1, 8), braille(0x01 + 0x02 + 0x04 + 0x40), "four lines fill the left column")
  t.eq(minimap.encode({ " b" }, 1, 1, 8), braille(0x08), "blanks leave dots dark")
  t.eq(minimap.encode({ "abcd" }, 2, 1, 8), braille(0x09) .. braille(0x09), "text spills into the next cell")
  t.eq(minimap.encode({ "abcd" }, 1, 2, 8), braille(0x09), "two columns per dot halve the width")
  -- ts=4 puts "x" at column 4 -> dot column 2 -> left dot of cell 1.
  t.eq(minimap.encode({ "\tx" }, 3, 2, 4), braille(0) .. braille(0x01) .. braille(0), "tabs are expanded")
  t.eq(minimap.encode({ "éé" }, 1, 1, 8), braille(0x09), "multi-byte characters count once")
  t.eq(minimap.encode({ string.rep("x", 100) }, 2, 1, 8), braille(0x09) .. braille(0x09), "text past the map is cut")
  t.eq(minimap.encode({}, 2, 1, 8), braille(0) .. braille(0), "empty rows are blank braille")
end)

t.describe("encode: each cell takes its most common group", function()
  local groups = { { "A", "A", "B" }, { false } }
  local text, spans = minimap.encode({ "abc", "" }, 2, 1, 8, groups)
  t.eq(text, braille(0x09) .. braille(0x01), "the dots are unchanged")
  t.eq(vim.inspect(spans), vim.inspect({ { 0, 1, "A" }, { 1, 2, "B" } }), "one span per group")

  _, spans = minimap.encode({ "abab", "cdcd" }, 2, 1, 8, { { "K", "K", "K", "K" }, { "K", "S", "K", "S" } })
  t.eq(vim.inspect(spans), vim.inspect({ { 0, 2, "K" } }), "neighbouring cells of one group merge")

  _, spans = minimap.encode({ "ab" }, 1, 1, 8, { {} })
  t.eq(vim.inspect(spans), vim.inspect({}), "uncoloured text gives no span")
end)

t.describe("layout: the map scrolls with the window", function()
  local l = minimap.layout({ height = 30, line_count = 100, topline = 1, botline = 30 })
  t.eq(l.offset, 0, "a map that fits starts at the top")
  t.eq(l.view_top, 0, "viewport from row 0")
  t.eq(l.view_bottom, 7, "30 lines cover 8 rows")

  l = minimap.layout({ height = 30, line_count = 4000, topline = 1, botline = 30 })
  t.eq(l.offset, 0, "at the top of a long buffer the map is at its top")

  l = minimap.layout({ height = 30, line_count = 4000, topline = 3971, botline = 4000 })
  t.eq(l.offset, 1000 - 30, "at the end the map is at its end")
  t.eq(l.view_bottom, 29, "and the viewport reaches the last row")

  for top = 1, 3971, 97 do
    l = minimap.layout({ height = 30, line_count = 4000, topline = top, botline = top + 29 })
    t.check(l.view_top >= 0 and l.view_bottom <= 29, "viewport stays on screen at line " .. top)
  end
end)

t.describe("the minimap float sits left of the vertical bar", function()
  vim.cmd("silent! only")
  local _, win = fill(500, "some text on line ")
  scroll.refresh()
  local float = float_of(win, "minimap")
  t.check(float ~= nil, "a minimap is drawn")
  local cfg = vim.api.nvim_win_get_config(float)
  local info = vim.fn.getwininfo(win)[1]
  t.eq(cfg.width, 20, "configured width")
  t.eq(cfg.col, info.width - 1 - 20, "left of the 1-column bar")
  t.eq(cfg.height, info.height, "full text height")

  local lines = vim.api.nvim_buf_get_lines(vim.api.nvim_win_get_buf(float), 0, -1, false)
  t.eq(#lines, info.height, "one line per row")
  t.eq(vim.fn.strchars(lines[1]), 20, "gutter + 19 braille cells")
  t.check(lines[1]:find(braille(0x09 + 0x12 + 0x24 + 0xC0), 1, true) ~= nil, "text renders as full cells")
end)

t.describe("the viewport is highlighted and follows scrolling", function()
  vim.cmd("silent! only")
  local _, win = fill(2000, "text ")
  vim.cmd("normal! gg")
  scroll.refresh()
  local fbuf = vim.api.nvim_win_get_buf(float_of(win, "minimap"))
  local function viewport_rows()
    local rows = {}
    for _, m in ipairs(vim.api.nvim_buf_get_extmarks(fbuf, -1, 0, -1, { details = true })) do
      if m[4].line_hl_group == "ScrollMinimapViewport" then
        rows[#rows + 1] = m[2]
      end
    end
    table.sort(rows)
    return rows
  end
  local height = vim.fn.getwininfo(win)[1].height
  local rows = viewport_rows()
  t.eq(rows[1], 0, "viewport starts at the top")
  t.eq(#rows, math.ceil(height / 4), "and covers the visible lines")

  vim.cmd("normal! G")
  scroll.refresh()
  rows = viewport_rows()
  t.eq(rows[#rows], height - 1, "at EOF the viewport is at the bottom")
end)

t.describe("edits re-render the map", function()
  vim.cmd("silent! only")
  local buf, win = fill(500, "x")
  vim.cmd("normal! gg")
  scroll.refresh()
  local fbuf = vim.api.nvim_win_get_buf(float_of(win, "minimap"))
  local before = vim.api.nvim_buf_get_lines(fbuf, 0, 1, false)[1]
  vim.api.nvim_buf_set_lines(buf, 0, 4, false, { "", "", "", "" })
  scroll.refresh()
  local after = vim.api.nvim_buf_get_lines(fbuf, 0, 1, false)[1]
  t.check(before ~= after, "the first row changed")
  t.eq(after, " " .. string.rep(braille(0), 19), "blank lines give a blank row")
end)

t.describe("git changes appear in the gutter", function()
  vim.cmd("silent! only")
  local buf, win = fill(500)
  package.loaded.gitsigns = {
    get_hunks = function()
      return { { type = "change", added = { start = 5, count = 1 }, removed = { start = 5, count = 1 } } }
    end,
  }
  vim.b[buf].gitsigns_status_dict = { head = "main" }
  vim.cmd("normal! gg")
  scroll.refresh()
  local fbuf = vim.api.nvim_win_get_buf(float_of(win, "minimap"))
  local found = nil
  for _, m in ipairs(vim.api.nvim_buf_get_extmarks(fbuf, -1, 0, -1, { details = true })) do
    if m[4].virt_text then
      found = { row = m[2], hl = m[4].virt_text[1][2] }
    end
  end
  t.check(found ~= nil, "a gutter mark is drawn")
  t.eq(found and found.row, 1, "line 5 is on the second row")
  t.eq(found and found.hl, "ScrollMarkChange", "as a change")
  package.loaded.gitsigns = nil
  vim.b[buf].gitsigns_status_dict = nil
end)

local function colour_marks(fbuf)
  local found = {}
  for _, m in ipairs(vim.api.nvim_buf_get_extmarks(fbuf, -1, 0, -1, { details = true })) do
    if m[4].hl_group and m[4].end_col then
      found[#found + 1] = { row = m[2], col = m[3], hl = m[4].hl_group }
    end
  end
  return found
end

t.describe("the map takes the buffer's treesitter colours", function()
  vim.cmd("silent! only")
  local lines = {}
  for i = 1, 200 do
    lines[i] = ("local v%d = 'text' -- note"):format(i)
  end
  local buf = vim.api.nvim_create_buf(true, false)
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
  local win = vim.api.nvim_get_current_win()
  vim.api.nvim_win_set_buf(win, buf)
  vim.treesitter.start(buf, "lua")
  vim.cmd("normal! gg")
  scroll.refresh()
  local fbuf = vim.api.nvim_win_get_buf(float_of(win, "minimap"))
  local groups = {}
  for _, m in ipairs(colour_marks(fbuf)) do
    if m.row == 0 then
      groups[#groups + 1] = m.hl
    end
  end
  -- "local" | " v1 = " | "'text'" | " -- note", 2 dot columns per cell.
  t.eq(groups[1], "@keyword.lua", "the row starts as a keyword")
  t.check(vim.tbl_contains(groups, "@string.lua"), "strings keep their colour")
  t.check(vim.tbl_contains(groups, "@comment.lua"), "and so do comments")

  config.options.minimap.colors = false
  scroll.refresh()
  t.eq(#colour_marks(fbuf), 0, "colors = false draws it plain")
  config.options.minimap.colors = true
  vim.treesitter.stop(buf)
end)

t.describe("without treesitter, :syntax colours the map", function()
  vim.cmd("silent! only")
  vim.cmd("syntax on")
  local buf, win = fill(200, "if x then ")
  vim.bo[buf].syntax = "lua"
  vim.cmd("normal! gg")
  scroll.refresh()
  local marks = colour_marks(vim.api.nvim_win_get_buf(float_of(win, "minimap")))
  t.check(#marks > 0, "cells are coloured")
  t.eq(marks[1] and marks[1].hl, "luaCond", "by syntax group")
  vim.cmd("syntax off")
end)

t.describe("the horizontal track stops at the minimap", function()
  vim.cmd("silent! only")
  local _, win = fill(50, string.rep("z", 400))
  vim.wo[win].wrap = false
  scroll.refresh()
  local h = render.compute(win).horizontal
  local map = render.compute(win).minimap
  t.eq(h.textoff + h.track, map.col, "the track ends where the minimap begins")
end)

t.describe("narrow windows get no minimap", function()
  vim.cmd("silent! only")
  local _, win = fill(500)
  vim.cmd("vsplit")
  local other = vim.api.nvim_get_current_win()
  vim.api.nvim_win_set_width(win, 40)
  scroll.refresh()
  t.eq(float_of(win, "minimap"), nil, "40 columns is below min_window_width")
  vim.api.nvim_win_close(other, true)
  scroll.refresh()
  t.check(float_of(win, "minimap") ~= nil, "widened to full width, it gets one")
end)

t.describe("the minimap does not auto-hide by default", function()
  vim.cmd("silent! only")
  local _, win = fill(500)
  scroll.refresh()
  render.hide_all()
  t.eq(vim.api.nvim_win_get_config(float_of(win, "vertical")).hide, true, "the scrollbar hides")
  t.eq(vim.api.nvim_win_get_config(float_of(win, "minimap")).hide, false, "the minimap stays")

  config.options.minimap.autohide = true
  render.hide_all()
  t.eq(vim.api.nvim_win_get_config(float_of(win, "minimap")).hide, true, "unless autohide is set")
  config.options.minimap.autohide = false
  scroll.refresh()
end)

t.describe("toggling removes and restores the minimap", function()
  vim.cmd("silent! only")
  local _, win = fill(500)
  scroll.refresh()
  vim.cmd("ScrollMinimapToggle")
  t.eq(float_of(win, "minimap"), nil, "toggled off: the float is gone")
  t.check(float_of(win, "vertical") ~= nil, "the scrollbar is untouched")
  vim.cmd("ScrollMinimapToggle")
  t.check(float_of(win, "minimap") ~= nil, "toggled on again")
end)

t.describe("clicking the minimap centres the view there", function()
  vim.cmd("silent! only")
  local _, win = fill(2000)
  vim.cmd("normal! gg")
  scroll.refresh()
  local height = vim.fn.getwininfo(win)[1].height
  mouse._minimap_jump(win, 20) -- map row 20 = line 81
  vim.cmd("redraw")
  local info = vim.fn.getwininfo(win)[1]
  t.eq(info.topline, 81 - math.floor(height / 2), "line 81 is centred")
  t.check(vim.fn.line(".") >= info.topline and vim.fn.line(".") <= info.botline, "the cursor came along")
end)

t.describe("dragging keeps the view even when the cursor was elsewhere", function()
  vim.cmd("silent! only")
  local _, win = fill(1000, string.rep("q", 300) .. " ")
  vim.wo[win].wrap = false
  for _, so in ipairs({ 0, 4, 999 }) do
    vim.o.scrolloff = so
    vim.o.sidescrolloff = so
    vim.cmd("normal! gg0")
    mouse._set_topline(win, 500)
    vim.cmd("redraw")
    t.eq(vim.fn.getwininfo(win)[1].topline, 500, "scrolled down stays put (so=" .. so .. ")")

    vim.cmd("normal! G")
    vim.cmd("redraw")
    mouse._set_topline(win, 300)
    vim.cmd("redraw")
    t.eq(vim.fn.getwininfo(win)[1].topline, 300, "scrolled up stays put (so=" .. so .. ")")

    vim.cmd("normal! 0")
    vim.cmd("redraw")
    mouse._set_leftcol(win, 150)
    vim.cmd("redraw")
    t.eq(vim.fn.getwininfo(win)[1].leftcol, 150, "scrolled right stays put (so=" .. so .. ")")
  end
  vim.o.scrolloff, vim.o.sidescrolloff = 0, 0
end)

t.describe("a short cursor line hands the cursor to a long one", function()
  vim.cmd("silent! only")
  local _, win = fill(100, string.rep("q", 300) .. " ")
  vim.wo[win].wrap = false
  vim.api.nvim_buf_set_lines(0, 4, 5, false, { "short" })
  vim.api.nvim_win_set_cursor(win, { 5, 0 })
  vim.cmd("redraw")
  mouse._set_leftcol(win, 150)
  vim.cmd("redraw")
  t.eq(vim.fn.getwininfo(win)[1].leftcol, 150, "the view scrolled right")
  t.check(vim.fn.line(".") ~= 5, "the cursor left the short line")
end)

t.describe("dragging stays put with wrapped lines", function()
  vim.cmd("silent! only")
  local _, win = fill(1000, string.rep("w", 250) .. " ")
  vim.wo[win].wrap = true
  vim.cmd("normal! G")
  vim.cmd("redraw")
  mouse._set_topline(win, 300)
  vim.cmd("redraw")
  t.eq(vim.fn.getwininfo(win)[1].topline, 300, "wrapped: scrolled up stays put")
end)

--- The minimap float of `win`, if it is on screen.
local function shown_map(win)
  local f = float_of(win, "minimap")
  return f and not vim.api.nvim_win_get_config(f).hide and f or nil
end

t.describe("the minimap only covers ordinary file buffers", function()
  vim.cmd("silent! only")
  local buf, win = fill(500)
  scroll.refresh()
  t.check(shown_map(win) ~= nil, "a file buffer gets a minimap")

  vim.bo[buf].filetype = "snacks_dashboard"
  scroll.refresh()
  t.eq(float_of(win, "minimap"), nil, "an excluded filetype does not")
  t.check(float_of(win, "vertical") ~= nil, "but keeps its vertical bar")
  vim.bo[buf].filetype = ""

  config.options.minimap.enabled_for = function(b)
    return b ~= buf
  end
  scroll.refresh()
  t.eq(float_of(win, "minimap"), nil, "`enabled_for` can turn it off")
  config.options.minimap.enabled_for = nil
end)

t.describe("a window that becomes a terminal loses the minimap", function()
  vim.cmd("silent! only")
  local buf = vim.api.nvim_create_buf(true, false)
  local win = vim.api.nvim_get_current_win()
  vim.api.nvim_win_set_buf(win, buf)
  scroll.refresh()
  t.check(float_of(win, "minimap") ~= nil, "an empty file buffer gets a minimap")

  -- As Snacks does it: the window exists first, the terminal comes after.
  local job = vim.fn.jobstart({ vim.v.progpath, "--clean", "--headless", "+sleep 2", "+qa!" }, { term = true })
  t.eq(vim.bo[buf].buftype, "terminal", "the buffer is a terminal now")
  vim.wait(200, function()
    return float_of(win, "minimap") == nil
  end)
  t.eq(float_of(win, "minimap"), nil, "TermOpen removed the minimap")
  vim.fn.jobstop(job)
end)

t.describe("the row holding the cursor is underlined", function()
  vim.cmd("silent! only")
  local _, win = fill(2000, "text ")
  vim.cmd("normal! gg")
  vim.api.nvim_win_set_cursor(win, { 10, 0 })
  scroll.refresh()
  local function cursor_rows()
    local fbuf = vim.api.nvim_win_get_buf(float_of(win, "minimap"))
    local rows = {}
    for _, m in ipairs(vim.api.nvim_buf_get_extmarks(fbuf, -1, 0, -1, { details = true })) do
      if m[4].line_hl_group == "ScrollMinimapCursor" then
        rows[#rows + 1] = m[2]
      end
    end
    return rows
  end
  t.eq(vim.inspect(cursor_rows()), vim.inspect({ 2 }), "line 10 is in row 2")
  vim.api.nvim_win_set_cursor(win, { 13, 0 })
  scroll.refresh()
  t.eq(vim.inspect(cursor_rows()), vim.inspect({ 3 }), "line 13 is in row 3")

  config.options.minimap.cursor = false
  scroll.refresh()
  t.eq(#cursor_rows(), 0, "no line with `cursor = false`")
  config.options.minimap.cursor = true
end)

t.describe("the minimap steps aside for the cursor and the selection", function()
  vim.cmd("silent! only")
  local _, win = fill(100, string.rep("x", 200))
  local map_col = vim.fn.getwininfo(win)[1].width - 1 - 20

  vim.wo[win].wrap = true
  scroll.refresh()
  t.check(shown_map(win) ~= nil, "shown while the cursor is clear")
  vim.api.nvim_win_set_cursor(win, { 1, map_col + 3 })
  scroll.refresh()
  t.eq(shown_map(win), nil, "hidden while the cursor is under it")
  t.check(float_of(win, "minimap") ~= nil, "hidden, not destroyed")
  vim.api.nvim_win_set_cursor(win, { 1, 0 })
  scroll.refresh()
  t.check(shown_map(win) ~= nil, "back once the cursor leaves")

  vim.wo[win].wrap = false
  config.options.minimap.dodge.margin = false
  vim.api.nvim_win_set_cursor(win, { 2, 0 })
  vim.api.nvim_feedkeys("V", "x", false)
  scroll.refresh()
  t.eq(shown_map(win), nil, "hidden under a linewise selection of long lines")
  vim.api.nvim_feedkeys("\27", "x", false)
  scroll.refresh()
  t.check(shown_map(win) ~= nil, "back after the selection ends")

  vim.api.nvim_buf_set_lines(0, 1, 2, false, { "short" })
  vim.api.nvim_win_set_cursor(win, { 2, 0 })
  vim.api.nvim_feedkeys("V", "x", false)
  scroll.refresh()
  t.check(shown_map(win) ~= nil, "a selection of short lines leaves it alone")
  vim.api.nvim_feedkeys("\27", "x", false)

  config.options.minimap.dodge.hide = false
  vim.wo[win].wrap = true
  vim.api.nvim_win_set_cursor(win, { 1, map_col + 3 })
  scroll.refresh()
  t.check(shown_map(win) ~= nil, "`dodge.hide = false` keeps it up")
  config.options.minimap.dodge = { margin = true, hide = true }
  vim.wo[win].wrap = false
end)

t.describe("the right margin keeps the cursor left of the minimap", function()
  vim.cmd("silent! only")
  local _, win = fill(100, string.rep("y", 300))
  local dodge = require("scroll.dodge")
  local info = vim.fn.getwininfo(win)[1]
  local map_col = info.width - 1 - 20
  vim.wo[win].sidescrolloff = 2

  for _, col in ipairs({ 10, map_col - 3, map_col, map_col + 10, 150, 299 }) do
    vim.api.nvim_win_set_cursor(win, { 1, col })
    dodge.keep_clear(win)
    local screen = col - vim.fn.winsaveview().leftcol
    t.check(screen <= map_col - 1 - 2, ("column %d is drawn at %d, left of the map at %d"):format(col, screen, map_col))
    t.check(screen >= 0, ("column %d is on screen"):format(col))
  end

  vim.fn.winrestview({ leftcol = 0 })
  vim.api.nvim_win_set_cursor(win, { 1, 10 })
  dodge.keep_clear(win)
  t.eq(vim.fn.winsaveview().leftcol, 0, "no scroll while the cursor is clear")

  config.options.minimap.dodge.margin = false
  vim.api.nvim_win_set_cursor(win, { 1, map_col + 5 })
  dodge.keep_clear(win)
  t.eq(vim.fn.winsaveview().leftcol, 0, "`dodge.margin = false` leaves the view alone")
  config.options.minimap.dodge.margin = true
  vim.wo[win].sidescrolloff = -1
end)

t.describe("a scrolled minimap float is put back", function()
  vim.cmd("silent! only")
  local _, win = fill(2000)
  scroll.refresh()
  local float = float_of(win, "minimap")
  vim.api.nvim_win_call(float, function()
    vim.fn.winrestview({ topline = 6 })
  end)
  t.eq(vim.fn.getwininfo(float)[1].topline, 6, "the float was scrolled")
  scroll.refresh()
  t.eq(vim.fn.getwininfo(float)[1].topline, 1, "the next refresh scrolls it back")
end)

t.describe("scrolling with the minimap stays cheap on a huge buffer", function()
  vim.cmd("silent! only")
  local _, win = fill(100000, "\tlocal value = compute(x) -- trailing text ")
  vim.api.nvim_win_set_cursor(win, { 50000, 0 })
  scroll.refresh()
  local steps = 200
  local start = vim.uv.hrtime()
  for _ = 1, steps do
    vim.cmd("normal! \5")
    scroll.refresh()
  end
  local ms = (vim.uv.hrtime() - start) / 1e6 / steps
  io.write(string.format("  (refresh with minimap on 100k lines: %.3f ms/step)\n", ms))
  t.check(ms < 2.0, string.format("refresh with minimap under 2ms (got %.3f ms)", ms))
end)

t.finish("minimap")
