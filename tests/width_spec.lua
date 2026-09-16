-- Run with: nvim --headless -u NONE -l tests/width_spec.lua
package.path = "lua/?.lua;lua/?/init.lua;" .. package.path
local t = dofile("tests/harness.lua")

local width = require("scroll.width")
require("scroll.config").setup({})

local win = vim.api.nvim_get_current_win()

local function make(lines)
  local buf = vim.api.nvim_create_buf(true, false)
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
  vim.api.nvim_win_set_buf(win, buf)
  return buf
end

t.describe("small buffers are measured synchronously and exactly", function()
  width.reset()
  local buf = make({ "short", string.rep("a", 120), "mid" })
  t.eq(width.get(buf, win), 120, "widest line wins")
end)

t.describe("display width, not byte length", function()
  width.reset()
  vim.o.tabstop = 8

  local buf = make({ "\tx" })
  t.eq(width.get(buf, win), 9, "a tab expands to the tabstop")

  width.reset()
  buf = make({ "你好" })
  t.eq(width.get(buf, win), 4, "double-width characters count twice")

  width.reset()
  buf = make({ "ééééé" })
  t.eq(width.get(buf, win), 5, "multibyte single-width characters count once")
end)

t.describe("tabstop is read from the measured buffer", function()
  width.reset()
  local buf = make({ "\tx" })
  vim.bo[buf].tabstop = 2
  t.eq(width.get(buf, win), 3, "uses the buffer's own tabstop, not the global one")
  vim.bo[buf].tabstop = 8
end)

t.describe("edits are picked up", function()
  width.reset()
  local buf = make({ "aaa", "bbb" })
  t.eq(width.get(buf, win), 3, "starts narrow")

  vim.api.nvim_buf_set_lines(buf, 0, 1, false, { string.rep("c", 200) })
  t.eq(width.get(buf, win), 200, "a newly widened line is reflected")

  vim.api.nvim_buf_set_lines(buf, 0, 1, false, { "aaa" })
  t.eq(width.get(buf, win), 3, "removing the widest line narrows it again")
end)

t.describe("large buffers scan in the background without blocking", function()
  width.reset()
  local lines = {}
  for i = 1, 30000 do
    lines[i] = string.rep("x", 40)
  end
  -- The widest line is far past the visible range, so it can only be found by
  -- the full scan.
  lines[25000] = string.rep("y", 500)
  local buf = make(lines)

  local start = vim.uv.hrtime()
  local first = width.get(buf, win)
  local ms = (vim.uv.hrtime() - start) / 1e6

  t.check(ms < 20, string.format("the first call does not block (%.2f ms)", ms))
  t.check(first >= 40, "an immediate estimate is available from the visible lines")

  -- Drive the event loop until the background scan lands.
  local deadline = vim.uv.now() + 5000
  while width.get(buf, win) < 500 and vim.uv.now() < deadline do
    vim.wait(20)
  end
  t.eq(width.get(buf, win), 500, "the background scan finds the off-screen widest line")
end)

t.describe("forget drops the cache and stops timers", function()
  width.reset()
  local buf = make({ string.rep("q", 77) })
  t.eq(width.get(buf, win), 77, "cached")
  width.forget(buf)
  t.eq(width.get(buf, win), 77, "recomputed cleanly after being forgotten")
end)

t.finish("width")
