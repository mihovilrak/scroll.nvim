-- Run with: nvim --headless -u NONE -l tests/integration_spec.lua
package.path = "lua/?.lua;lua/?/init.lua;" .. package.path
local t = dofile("tests/harness.lua")

vim.o.lines, vim.o.columns = 40, 120
vim.o.laststatus, vim.o.swapfile = 2, false
vim.cmd("redraw") -- flush the resize; see minimap_spec.lua

local scroll = require("scroll")
local render = require("scroll.render")
local measure = require("scroll.measure")

--- The float that carries each bar -- i.e. where the *track* is drawn.
local function tracks(win)
  local out = {}
  for _, w in ipairs(vim.api.nvim_tabpage_list_wins(0)) do
    local parent, orientation = render.owner_of(w)
    if parent == win then
      local cfg = vim.api.nvim_win_get_config(w)
      if not cfg.hide then
        out[orientation] = cfg
      end
    end
  end
  return out
end

--- Where the *thumb* sits inside the track. The float spans the whole track,
--- so thumb placement lives in the computed geometry rather than the float.
local function thumbs(win)
  return render.compute(win)
end

local function fill(n, text)
  local lines = {}
  for i = 1, n do
    lines[i] = (text or "line ") .. i
  end
  local buf = vim.api.nvim_create_buf(true, false)
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
  vim.api.nvim_win_set_buf(vim.api.nvim_get_current_win(), buf)
  return buf
end

scroll.setup({ visibility = "always", mouse = false })

t.describe("vertical bar tracks the viewport", function()
  vim.cmd("silent! only")
  fill(500)
  local win = vim.api.nvim_get_current_win()
  vim.wo[win].wrap = false

  vim.cmd("normal! gg")
  scroll.refresh()
  local track = tracks(win).vertical
  t.check(track ~= nil, "a vertical bar is drawn for a 500-line buffer")
  t.eq(track.col, vim.api.nvim_win_get_width(win) - 1, "track sits in the last column")
  t.eq(track.height, vim.fn.getwininfo(win)[1].height, "track spans the full text height")
  t.eq(thumbs(win).vertical.pos, 0, "at the top of the buffer the thumb is at row 0")

  vim.cmd("normal! G")
  scroll.refresh()
  local info = vim.fn.getwininfo(win)[1]
  local v = thumbs(win).vertical
  t.eq(v.pos + v.size, info.height, "at EOF the thumb is flush with the bottom of the track")
end)

t.describe("no vertical bar when the content fits", function()
  vim.cmd("silent! only")
  fill(5)
  local win = vim.api.nvim_get_current_win()
  scroll.refresh()
  t.eq(tracks(win).vertical, nil, "5 lines in a 38-row window needs no bar")
end)

t.describe("horizontal bar appears only with overflow and nowrap", function()
  vim.cmd("silent! only")
  fill(50, string.rep("x", 400))
  local win = vim.api.nvim_get_current_win()

  vim.wo[win].wrap = false
  scroll.refresh()
  local track = tracks(win).horizontal
  t.check(track ~= nil, "long lines with wrap off get a horizontal bar")
  t.eq(track.row, vim.fn.getwininfo(win)[1].height - 1, "track sits on the last text row")
  t.eq(track.col, vim.fn.getwininfo(win)[1].textoff, "track starts after the gutter")

  vim.wo[win].wrap = true
  scroll.refresh()
  t.eq(tracks(win).horizontal, nil, "wrapped text has nothing to scroll sideways")
end)

t.describe("horizontal thumb follows leftcol", function()
  vim.cmd("silent! only")
  fill(50, string.rep("y", 400))
  local win = vim.api.nvim_get_current_win()
  vim.wo[win].wrap = false

  vim.api.nvim_win_set_cursor(win, { 1, 0 })
  scroll.refresh()
  t.eq(thumbs(win).horizontal.pos, 0, "leftcol 0 -> thumb at the track start")

  -- The cursor has to travel too; Nvim clamps leftcol to keep it on screen.
  vim.api.nvim_win_set_cursor(win, { 1, 380 })
  vim.api.nvim_win_call(win, function()
    vim.cmd("normal! ze")
  end)
  scroll.refresh()
  local info = vim.fn.getwininfo(win)[1]
  t.check(info.leftcol > 0, "the window actually scrolled right")
  local h = thumbs(win).horizontal
  t.check(h.pos > 0, "scrolling right moves the thumb right")
  t.check(h.pos + h.size <= h.track, "the thumb stays inside its track")
end)

t.describe("the gutter offsets the horizontal track", function()
  vim.cmd("silent! only")
  fill(50, string.rep("z", 400))
  local win = vim.api.nvim_get_current_win()
  vim.wo[win].wrap = false
  vim.wo[win].number = true
  vim.wo[win].signcolumn = "yes"
  scroll.refresh()

  local info = vim.fn.getwininfo(win)[1]
  t.check(info.textoff > 0, "number + signcolumn produce a gutter")
  t.eq(tracks(win).horizontal.col, info.textoff, "track starts at textoff, not column 0")
  vim.wo[win].number = false
  vim.wo[win].signcolumn = "auto"
end)

t.describe("one buffer in two splits gets independent bars", function()
  vim.cmd("silent! only")
  local buf = fill(500)
  local first = vim.api.nvim_get_current_win()
  vim.cmd("split")
  local second = vim.api.nvim_get_current_win()
  vim.api.nvim_win_set_buf(second, buf)

  vim.api.nvim_win_call(first, function()
    vim.cmd("normal! G")
  end)
  vim.api.nvim_win_call(second, function()
    vim.cmd("normal! gg")
  end)
  scroll.refresh()

  local a, b = thumbs(first).vertical, thumbs(second).vertical
  t.check(a ~= nil and b ~= nil, "both splits get their own bar")
  t.eq(b.pos, 0, "the split showing the top of the buffer has its thumb at row 0")
  t.check(a.pos > 0, "the split at EOF has its thumb lower down")
  vim.cmd("silent! only")
end)

t.describe("winbar shifts the track down", function()
  vim.cmd("silent! only")
  fill(500)
  local win = vim.api.nvim_get_current_win()
  vim.wo[win].winbar = "%f"
  vim.cmd("normal! gg")
  scroll.refresh()
  t.eq(tracks(win).vertical.row, 1, "a winbar pushes the track off row 0")
  vim.wo[win].winbar = ""
end)

t.describe("floating windows get no bars", function()
  vim.cmd("silent! only")
  fill(500)
  local fbuf = vim.api.nvim_create_buf(false, true)
  local lines = {}
  for i = 1, 500 do
    lines[i] = "float line " .. i
  end
  vim.api.nvim_buf_set_lines(fbuf, 0, -1, false, lines)
  local fwin = vim.api.nvim_open_win(fbuf, false, {
    relative = "editor", row = 2, col = 2, width = 30, height = 10,
  })
  scroll.refresh()
  local b = tracks(fwin)
  t.eq(b.vertical, nil, "no vertical bar on a float")
  t.eq(b.horizontal, nil, "no horizontal bar on a float")
  vim.api.nvim_win_close(fwin, true)
end)

t.describe("excluded buffers are skipped", function()
  vim.cmd("silent! only")
  fill(500)
  local win = vim.api.nvim_get_current_win()
  vim.bo[vim.api.nvim_win_get_buf(win)].buftype = "nofile"
  scroll.refresh()
  t.eq(tracks(win).vertical, nil, "a nofile buffer gets no bar")
end)

t.describe("wrapping is measured, not assumed", function()
  vim.cmd("silent! only")
  -- Sized so the thumb is comfortably bigger than the 1-row floor in the
  -- unwrapped case; otherwise both sides clamp to 1 and prove nothing.
  local count = 60
  fill(count, string.rep("w", 300))
  local win = vim.api.nvim_get_current_win()
  vim.cmd("normal! gg")

  vim.wo[win].wrap = false
  scroll.refresh()
  local flat = thumbs(win).vertical
  local flat_total = measure.vertical(win).total

  vim.wo[win].wrap = true
  scroll.refresh()
  local wrapped = thumbs(win).vertical
  local wrapped_total = measure.vertical(win).total

  t.eq(flat_total, count, "unwrapped, one screen row per line")
  t.check(wrapped_total > flat_total, "wrapping makes the document taller")
  t.check(wrapped ~= nil and flat ~= nil, "a bar is drawn either way")
  t.check(wrapped.size < flat.size, "wrapped content is taller, so its thumb is smaller")
end)

t.describe("folds are measured", function()
  vim.cmd("silent! only")
  fill(500)
  local win = vim.api.nvim_get_current_win()
  vim.wo[win].wrap = false
  vim.cmd("normal! gg")
  scroll.refresh()
  local before = thumbs(win).vertical

  vim.wo[win].foldmethod = "manual"
  vim.cmd("100,400fold")
  scroll.refresh()
  local after = thumbs(win).vertical

  -- Folding 300 of 500 lines away leaves ~200 display rows, so the thumb
  -- covers a much larger share of the track.
  t.check(after.size > before.size, "closing a large fold grows the thumb")
  vim.cmd("normal! zE")
end)

t.describe("the thumb never leaves the track, at any scroll position", function()
  vim.cmd("silent! only")
  fill(1000)
  local win = vim.api.nvim_get_current_win()
  vim.wo[win].wrap = false
  local height = vim.fn.getwininfo(win)[1].height
  for line = 1, 1000, 37 do
    vim.api.nvim_win_set_cursor(win, { line, 0 })
    scroll.refresh()
    local v = thumbs(win).vertical
    t.check(v.pos >= 0 and v.pos + v.size <= height, "thumb inside the track at line " .. line)
  end
end)

t.finish("integration")
