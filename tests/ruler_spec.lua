-- Run with: nvim --headless -u NONE -l tests/ruler_spec.lua
package.path = "lua/?.lua;lua/?/init.lua;" .. package.path
local t = dofile("tests/harness.lua")

vim.o.lines, vim.o.columns = 40, 120
vim.o.laststatus, vim.o.swapfile = 2, false

local scroll = require("scroll")
local config = require("scroll.config")
local render = require("scroll.render")
local ruler = require("scroll.ruler")
local measure = require("scroll.measure")

local ns = vim.api.nvim_create_namespace("scroll.ruler.spec")

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

--- Ruler cells for `win`, keyed "row:col" -> highlight group.
local function cells(win)
  scroll.refresh()
  local m = measure.vertical(win)
  local out, list = {}, ruler.cells(win, vim.fn.getwininfo(win)[1].height, m.total)
  for _, c in ipairs(list) do
    out[c.row .. ":" .. c.col] = c.hl
  end
  return out, list
end

local function count(tbl)
  local n = 0
  for _ in pairs(tbl) do
    n = n + 1
  end
  return n
end

local function set_diagnostics(buf, items)
  local diags = {}
  for i, item in ipairs(items) do
    diags[i] = { lnum = item[1] - 1, col = 0, severity = item[2], message = "m" .. i }
  end
  vim.diagnostic.set(ns, buf, diags)
end

--- The bar float drawn for `win`, if any.
local function vertical_float(win)
  for _, w in ipairs(vim.api.nvim_tabpage_list_wins(0)) do
    local parent, orientation = render.owner_of(w)
    if parent == win and orientation == "vertical" then
      return w
    end
  end
end

scroll.setup({ visibility = "always", mouse = false })
local E, W, H = vim.diagnostic.severity.ERROR, vim.diagnostic.severity.WARN, vim.diagnostic.severity.HINT

t.describe("diagnostics land on the rows of their lines", function()
  vim.cmd("silent! only")
  local buf, win = fill(500)
  vim.wo[win].wrap = false
  local height = vim.fn.getwininfo(win)[1].height
  set_diagnostics(buf, { { 1, E }, { 250, W }, { 500, H } })

  local got = cells(win)
  t.eq(count(got), 3, "three diagnostics, three cells")
  t.eq(got["0:0"], "ScrollMarkError", "line 1 is on the first row")
  t.eq(got[math.floor(249 * height / 500) .. ":0"], "ScrollMarkWarn", "line 250 is halfway down")
  t.eq(got[(height - 1) .. ":0"], "ScrollMarkHint", "the last line is on the last row")
end)

t.describe("the most severe mark wins a shared cell", function()
  vim.cmd("silent! only")
  local buf, win = fill(500)
  -- Lines 1 and 2 share row 0 of a ~38-row track.
  set_diagnostics(buf, { { 1, H }, { 2, E }, { 3, W } })
  local got = cells(win)
  t.eq(count(got), 1, "one cell")
  t.eq(got["0:0"], "ScrollMarkError", "error beats warning and hint")
end)

t.describe("filtering by severity", function()
  vim.cmd("silent! only")
  local buf, win = fill(500)
  config.options.marks.diagnostics.severity = { min = W }
  set_diagnostics(buf, { { 1, H }, { 400, E } })
  local got = cells(win)
  t.eq(count(got), 1, "the hint is filtered out")
  config.options.marks.diagnostics.severity = nil
end)

t.describe("disabled diagnostics are not marked", function()
  vim.cmd("silent! only")
  local buf, win = fill(500)
  set_diagnostics(buf, { { 1, E } })
  vim.diagnostic.enable(false, { bufnr = buf })
  vim.api.nvim_exec_autocmds("DiagnosticChanged", { buffer = buf })
  t.eq(count(cells(win)), 0, "no marks while diagnostics are disabled")
  vim.diagnostic.enable(true, { bufnr = buf })
end)

t.describe("marks are drawn into the bar float", function()
  vim.cmd("silent! only")
  local buf, win = fill(500)
  set_diagnostics(buf, { { 250, E } })
  cells(win)
  local float = vertical_float(win)
  t.check(float ~= nil, "the vertical bar exists")
  local fbuf = vim.api.nvim_win_get_buf(float)
  local found = false
  for _, mark in ipairs(vim.api.nvim_buf_get_extmarks(fbuf, -1, 0, -1, { details = true })) do
    local d = mark[4]
    if d.virt_text and d.virt_text[1][2] == "ScrollMarkError" then
      found = d.virt_text_pos == "overlay" and d.virt_text[1][1] == "━"
    end
  end
  t.check(found, "an overlay extmark carries the error tick")
end)

t.describe("search matches are marked only while highlighted", function()
  vim.cmd("silent! only")
  local _, win = fill(500)
  vim.api.nvim_buf_set_lines(0, 299, 300, false, { "needle here" })
  vim.o.hlsearch = true
  vim.fn.setreg("/", "needle")
  vim.v.hlsearch = 1

  local got = cells(win)
  t.eq(count(got), 1, "one matching line, one cell")
  local _, list = cells(win)
  t.eq(list[1].hl, "ScrollMarkSearch", "it is a search mark")

  vim.v.hlsearch = 0
  t.eq(count(cells(win)), 0, ":nohlsearch clears the marks")

  vim.v.hlsearch = 1
  vim.fn.setreg("/", "absent")
  t.eq(count(cells(win)), 0, "a pattern with no matches has no marks")
end)

t.describe("search follows 'ignorecase' and 'smartcase'", function()
  vim.cmd("silent! only")
  local _, win = fill(500)
  vim.api.nvim_buf_set_lines(0, 99, 100, false, { "Needle" })
  vim.api.nvim_buf_set_lines(0, 399, 400, false, { "needle" })
  vim.o.hlsearch = true
  vim.v.hlsearch = 1

  vim.o.ignorecase, vim.o.smartcase = false, false
  vim.fn.setreg("/", "needle")
  t.eq(count(cells(win)), 1, "case-sensitive: lowercase only")

  vim.o.ignorecase = true
  t.eq(count(cells(win)), 2, "ignorecase: both")

  vim.o.smartcase = true
  vim.fn.setreg("/", "Needle")
  t.eq(count(cells(win)), 1, "smartcase with an uppercase letter: exact case only")

  vim.o.ignorecase, vim.o.smartcase = false, false
  vim.v.hlsearch = 0
end)

t.describe("large buffers are searched in the background", function()
  vim.cmd("silent! only")
  local _, win = fill(20000)
  vim.api.nvim_buf_set_lines(0, 14999, 15000, false, { "needle" })
  vim.o.hlsearch = true
  vim.fn.setreg("/", "needle")
  vim.v.hlsearch = 1

  cells(win)
  local done = vim.wait(2000, function()
    return count(cells(win)) == 1
  end, 10)
  t.check(done, "the match appears once the scan finishes")
  vim.v.hlsearch = 0
end)

t.describe("marks follow folds", function()
  vim.cmd("silent! only")
  local buf, win = fill(500)
  vim.wo[win].wrap = false
  vim.wo[win].foldmethod = "manual"
  local height = vim.fn.getwininfo(win)[1].height
  set_diagnostics(buf, { { 450, E } })
  cells(win)

  -- Folds are opened and closed where the cursor is, so the fold is on
  -- screen when it changes.
  vim.api.nvim_win_set_cursor(win, { 100, 0 })
  vim.cmd("normal! zt")
  measure.vertical(win)
  vim.cmd("100,400fold")
  local total = measure.vertical(win).total
  t.eq(total, 200, "closing the fold is noticed without any option changing")
  local _, list = cells(win)
  -- 450 - 1 - 300 folded-away lines = 149 rows above it, out of 200.
  t.eq(list[1].row, math.floor(149 * height / 200), "the mark moves up with the fold closed")

  vim.cmd("100foldopen")
  t.eq(measure.vertical(win).total, 500, "opening it is noticed too")
  _, list = cells(win)
  t.eq(list[1].row, math.floor(449 * height / 500), "and the mark moves back")
  vim.cmd("normal! zE")
end)

t.describe("scrolling past folds is not mistaken for a fold change", function()
  vim.cmd("silent! only")
  local _, win = fill(500)
  vim.wo[win].foldmethod = "manual"
  vim.cmd("50,60fold")
  vim.cmd("200,300fold")
  vim.cmd("normal! gg")
  measure.vertical(win)
  local sig = measure.signature(win)
  for line = 1, 500, 40 do
    vim.api.nvim_win_set_cursor(win, { line, 0 })
    measure.vertical(win)
  end
  t.eq(measure.signature(win), sig, "scrolling keeps the cached measurement")
end)

t.describe("git marks use their own column on a wide track", function()
  vim.cmd("silent! only")
  local buf, win = fill(500)
  local height = vim.fn.getwininfo(win)[1].height
  config.options.vertical.width = 2
  -- Stand in for gitsigns so this runs without git.
  package.loaded.gitsigns = {
    get_hunks = function()
      return {
        { type = "add", added = { start = 1, count = 2 }, removed = { start = 0, count = 0 } },
        { type = "delete", added = { start = 399, count = 0 }, removed = { start = 400, count = 3 } },
      }
    end,
  }
  vim.b[buf].gitsigns_status_dict = { head = "main" }
  set_diagnostics(buf, { { 1, E } })
  vim.api.nvim_exec_autocmds("User", { pattern = "GitSignsUpdate", data = { buffer = buf } })

  local got = cells(win)
  t.eq(got["0:0"], "ScrollMarkAdd", "the added hunk is in the left column")
  t.eq(got["0:1"], "ScrollMarkError", "the diagnostic keeps the right column")
  t.eq(got[math.floor(399 * height / 500) .. ":0"], "ScrollMarkDelete", "the deletion is marked below")
  t.eq(count(got), 3, "three cells in all")

  config.options.vertical.width = 1
  got = cells(win)
  t.eq(count(got), 2, "on a 1-column track line 1's marks share a cell")
  t.eq(got["0:0"], "ScrollMarkError", "and the diagnostic wins")

  package.loaded.gitsigns = nil
  vim.b[buf].gitsigns_status_dict = nil
  vim.diagnostic.reset(ns, buf)
end)

t.describe("without gitsigns, the buffer is diffed against the index", function()
  if vim.fn.executable("git") == 0 then
    io.write("  (skipped: no git)\n")
    return
  end
  vim.cmd("silent! only")
  local dir = vim.fn.tempname()
  vim.fn.mkdir(dir, "p")
  local function git(...)
    local r = vim.system({ "git", "-C", dir, ... }, { text = true }):wait()
    assert(r.code == 0, r.stderr)
  end
  local lines = {}
  for i = 1, 500 do
    lines[i] = "line " .. i
  end
  vim.fn.writefile(lines, dir .. "/file.txt")
  git("init", "-q")
  git("-c", "user.email=t@t", "-c", "user.name=t", "add", "file.txt")

  vim.cmd("edit " .. vim.fn.fnameescape(dir .. "/file.txt"))
  local win = vim.api.nvim_get_current_win()
  local height = vim.fn.getwininfo(win)[1].height
  config.options.marks.git.debounce = 10

  cells(win)
  vim.wait(300, function()
    return false
  end, 10)
  t.eq(count(cells(win)), 0, "an unmodified file has no git marks")

  vim.api.nvim_buf_set_lines(0, 249, 250, false, { "changed" })
  vim.api.nvim_buf_set_lines(0, 399, 399, false, { "inserted" })
  local got
  local ok = vim.wait(3000, function()
    got = cells(win)
    return count(got) == 2
  end, 10)
  t.check(ok, "unsaved edits are marked once the debounce passes")
  t.eq(got[math.floor(249 * height / 501) .. ":0"], "ScrollMarkChange", "the edited line is a change")
  t.eq(got[math.floor(399 * height / 501) .. ":0"], "ScrollMarkAdd", "the inserted line is an add")

  vim.cmd("bwipeout!")
  vim.fn.delete(dir, "rf")
  config.options.marks.git.debounce = 200
end)

t.describe("files outside a repository get no git marks", function()
  vim.cmd("silent! only")
  local file = vim.fn.tempname() .. ".txt"
  local lines = {}
  for i = 1, 500 do
    lines[i] = "x" .. i
  end
  vim.fn.writefile(lines, file)
  vim.cmd("edit " .. vim.fn.fnameescape(file))
  local win = vim.api.nvim_get_current_win()
  cells(win)
  vim.wait(1000, function()
    return false
  end, 50)
  vim.api.nvim_buf_set_lines(0, 0, 1, false, { "edited" })
  t.eq(count(cells(win)), 0, "no index, no marks")
  vim.cmd("bwipeout!")
  vim.fn.delete(file)
end)

t.describe("background mark updates do not wake hidden bars", function()
  vim.cmd("silent! only")
  local buf, win = fill(500)
  config.options.visibility = "auto"
  scroll.refresh()
  -- Let the activity from opening the buffer run its course first.
  vim.wait(50, function()
    return false
  end)
  render.hide_all()
  local float = vertical_float(win)
  t.check(float and vim.api.nvim_win_get_config(float).hide, "the bar starts hidden")

  set_diagnostics(buf, { { 10, E } })
  vim.wait(50, function()
    return false
  end)
  t.check(vim.api.nvim_win_get_config(float).hide, "a DiagnosticChanged leaves it hidden")
  config.options.visibility = "always"
  vim.diagnostic.reset(ns, buf)
end)

t.describe("marks.enabled = false turns the ruler off", function()
  vim.cmd("silent! only")
  local buf, win = fill(500)
  set_diagnostics(buf, { { 10, E } })
  config.options.marks.enabled = false
  t.eq(count(cells(win)), 0, "no cells")
  config.options.marks.enabled = true
  vim.diagnostic.reset(ns, buf)
end)

t.describe("mark placement stays cheap on a huge wrapped buffer", function()
  vim.cmd("silent! only")
  local _, win = fill(100000, string.rep("w", 150) .. " ")
  vim.wo[win].wrap = true
  local buf = vim.api.nvim_get_current_buf()
  local items = {}
  for i = 1, 1000 do
    items[i] = { i * 97, E }
  end
  set_diagnostics(buf, items)
  vim.api.nvim_win_set_cursor(win, { 50000, 0 })
  scroll.refresh()

  -- Scrolling must reuse the placed cells rather than re-placing them.
  local steps = 200
  local start = vim.uv.hrtime()
  for _ = 1, steps do
    vim.cmd("normal! \5")
    scroll.refresh()
  end
  local ms = (vim.uv.hrtime() - start) / 1e6 / steps
  io.write(string.format("  (refresh with 1000 marks on 100k wrapped lines: %.3f ms/step)\n", ms))
  t.check(ms < 2.0, string.format("refresh with marks under 2ms (got %.3f ms)", ms))
  vim.diagnostic.reset(ns, buf)
end)

t.finish("ruler")
