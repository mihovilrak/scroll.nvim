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

scroll.setup({ visibility = "always", mouse = false, minimap = { enabled = true, min_window_width = 50 } })

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
