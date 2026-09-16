-- Run with: nvim --headless -u NONE -l tests/measure_spec.lua
--
-- The incremental "telescoping" in measure.lua is the riskiest code in the
-- plugin: it maintains `above` by accumulating deltas instead of measuring
-- from the start of the buffer, so any error would silently accumulate. These
-- tests check it against ground truth at every step, and pin the performance
-- that motivated it in the first place.
package.path = "lua/?.lua;lua/?/init.lua;" .. package.path
local t = dofile("tests/harness.lua")

local measure = require("scroll.measure")
require("scroll.config").setup({})

local function setup_buf(n, text)
  local lines = {}
  for i = 1, n do
    lines[i] = (text or "line ") .. i
  end
  local buf = vim.api.nvim_create_buf(true, false)
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
  vim.api.nvim_win_set_buf(vim.api.nvim_get_current_win(), buf)
  return buf, vim.api.nvim_get_current_win()
end

--- Ground truth, measured from the start of the buffer every time.
local function truth(win)
  local v = vim.api.nvim_win_call(win, vim.fn.winsaveview)
  local rows = vim.api.nvim_win_text_height(win, {
    start_row = 0,
    end_row = v.topline - 1,
    end_vcol = v.skipcol,
  }).all
  return rows - (v.topfill or 0)
end

t.describe("telescoping matches absolute measurement while wrapped", function()
  measure.reset()
  local _, win = setup_buf(400, string.rep("m", 250))
  vim.wo[win].wrap = true

  -- Walk forwards, then backwards, through many toplines without ever
  -- resetting the cache. Any drift in the accumulated value shows up here.
  local toplines = {}
  for line = 1, 400, 13 do
    toplines[#toplines + 1] = line
  end
  for line = 400, 1, -29 do
    toplines[#toplines + 1] = line
  end

  for _, line in ipairs(toplines) do
    vim.api.nvim_win_call(win, function()
      vim.fn.winrestview({ topline = line, lnum = line })
    end)
    local got = measure.vertical(win).offset
    t.eq(got, truth(win), "above at topline " .. line)
  end
end)

t.describe("telescoping matches absolute measurement with folds", function()
  measure.reset()
  local _, win = setup_buf(400)
  vim.wo[win].wrap = false
  vim.wo[win].foldmethod = "manual"
  vim.api.nvim_win_call(win, function()
    vim.cmd("50,150fold")
    vim.cmd("200,260fold")
  end)

  for line = 1, 400, 17 do
    vim.api.nvim_win_call(win, function()
      vim.fn.winrestview({ topline = line, lnum = line })
    end)
    t.eq(measure.vertical(win).offset, truth(win), "above with folds at topline " .. line)
  end
  vim.api.nvim_win_call(win, function()
    vim.cmd("normal! zE")
  end)
end)

t.describe("the fast path agrees with the measured path", function()
  measure.reset()
  local buf, win = setup_buf(2000)
  vim.wo[win].wrap = false
  local m = measure.vertical(win)
  t.eq(m.total, vim.api.nvim_buf_line_count(buf), "one screen row per line")

  for line = 1, 2000, 97 do
    vim.api.nvim_win_call(win, function()
      vim.fn.winrestview({ topline = line, lnum = line })
    end)
    t.eq(measure.vertical(win).offset, line - 1, "fast path above at topline " .. line)
    t.eq(measure.vertical(win).offset, truth(win), "fast path matches truth at topline " .. line)
  end
end)

t.describe("edits invalidate the cached total", function()
  measure.reset()
  local buf, win = setup_buf(100)
  vim.wo[win].wrap = false
  t.eq(measure.vertical(win).total, 100, "starts at 100 rows")

  vim.api.nvim_buf_set_lines(buf, 0, 0, false, { "new", "lines" })
  t.eq(measure.vertical(win).total, 102, "total follows the edit")

  vim.api.nvim_buf_set_lines(buf, 0, 50, false, {})
  t.eq(measure.vertical(win).total, 52, "total follows a deletion")
end)

t.describe("a refresh on a huge wrapped buffer stays cheap", function()
  measure.reset()
  local _, win = setup_buf(100000, string.rep("p", 200))
  vim.wo[win].wrap = true

  -- Prime the cache: the first call pays for the one-off total measurement.
  vim.api.nvim_win_call(win, function()
    vim.fn.winrestview({ topline = 50000, lnum = 50000 })
  end)
  measure.vertical(win)

  -- Now scroll the way a user does, a line at a time, and time the steady state.
  local start = vim.uv.hrtime()
  local steps = 200
  for i = 1, steps do
    vim.api.nvim_win_call(win, function()
      vim.fn.winrestview({ topline = 50000 + i, lnum = 50000 + i })
    end)
    measure.vertical(win)
  end
  local ms = (vim.uv.hrtime() - start) / 1e6 / steps

  -- Measuring from the start of the buffer here costs ~14ms per call; the
  -- telescoping should be orders of magnitude below that.
  io.write(string.format("  (scroll refresh on 100k wrapped lines: %.4f ms/step)\n", ms))
  t.check(ms < 1.0, string.format("steady-state scroll refresh under 1ms (got %.4f ms)", ms))
end)

t.finish("measure")
