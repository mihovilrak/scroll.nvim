-- Run with: nvim --headless -u NONE -l tests/scope_spec.lua
package.path = "lua/?.lua;lua/?/init.lua;" .. package.path
local t = dofile("tests/harness.lua")

vim.o.laststatus, vim.o.swapfile = 2, false

local scroll = require("scroll")
local scope = require("scroll.marks.scope")
local ruler = require("scroll.ruler")

scroll.setup({ visibility = "always", mouse = false })

local source = {
  "local M = {}", -- 1
  "", -- 2
  "local function helper(x)", -- 3
  "  if x then", -- 4
  "    print(x)", -- 5
  "  else", -- 6
  "    print(M.format(", -- 7
  "      x", -- 8
  "    ))", -- 9
  "  end", -- 10
  "  return x", -- 11
  "end", -- 12
  "", -- 13
  "return M", -- 14
}

local buf = vim.api.nvim_create_buf(true, false)
vim.api.nvim_buf_set_lines(buf, 0, -1, false, source)
local win = vim.api.nvim_get_current_win()
vim.api.nvim_win_set_buf(win, buf)
vim.treesitter.start(buf, "lua")
vim.treesitter.highlighter.active[buf].tree:parse(true)

--- Scope lines (1-based) around the cursor at line `l`, column `c`.
local function around(l, c)
  vim.api.nvim_win_set_cursor(win, { l, c })
  local ranges = scope.get(buf, nil, win)
  if #ranges == 0 then
    return "none"
  end
  return ranges[1].first .. "-" .. ranges[2].first
end

t.describe("the innermost block around the cursor", function()
  -- Lua's grammar has no node for the `then` branch, so that is the whole
  -- `if`; the `else` branch is its own node, ending before `end`.
  t.eq(around(5, 4), "4-10", "inside the `then` branch: the `if` statement")
  t.eq(around(8, 6), "6-9", "inside a multi-line call in the `else`: the `else`, not the call")
  t.eq(around(11, 2), "3-12", "in the function body: the function")
  t.eq(around(4, 0), "4-10", "in the indent of the `if` line: the whole `if` statement")
  t.eq(around(1, 0), "none", "at top level: nothing")
  t.eq(around(14, 0), "none", "after the function: nothing")
end)

t.describe("only the current window shows a scope", function()
  vim.api.nvim_win_set_cursor(win, { 5, 4 })
  local ranges = scope.get(buf, nil, win + 1000)
  t.eq(#ranges, 0, "another window gets none")
end)

t.describe("no treesitter, no scope", function()
  local plain = vim.api.nvim_create_buf(true, false)
  vim.api.nvim_buf_set_lines(plain, 0, -1, false, source)
  vim.api.nvim_win_set_buf(win, plain)
  vim.api.nvim_win_set_cursor(win, { 5, 4 })
  t.eq(#scope.get(plain, nil, win), 0, "a buffer without a highlighter")
  vim.api.nvim_win_set_buf(win, buf)
end)

t.describe("node types are matched by word", function()
  local opts = require("scroll.config").options.marks.scope
  local saved = opts.node_types
  opts.node_types = { "function" }
  t.eq(around(5, 4), "3-12", "with only `function`, the `if` is skipped")
  opts.node_types = { "print" }
  t.eq(around(5, 4), "none", "no node type contains the word")
  opts.node_types = saved
end)

t.describe("the ruler draws the scope's ends", function()
  local long = {}
  for i = 1, 200 do
    long[i] = "x = " .. i
  end
  vim.api.nvim_buf_set_lines(buf, #source, -1, false, long)
  vim.treesitter.highlighter.active[buf].tree:parse(true)
  vim.api.nvim_win_set_cursor(win, { 5, 4 })
  local height = vim.fn.getwininfo(win)[1].height
  local cells = ruler.cells(win, height, vim.api.nvim_buf_line_count(buf), nil)
  local scope_cells = vim.tbl_filter(function(c)
    return c.hl == "ScrollMarkScope"
  end, cells)
  t.check(#scope_cells >= 1, "the scope is marked on the track")
  t.eq(scope_cells[1] and scope_cells[1].char, "─", "with the scope glyph")

  require("scroll.config").options.marks.scope.enabled = false
  cells = ruler.cells(win, height, vim.api.nvim_buf_line_count(buf), nil)
  t.eq(
    #vim.tbl_filter(function(c)
      return c.hl == "ScrollMarkScope"
    end, cells),
    0,
    "and not when disabled"
  )
  require("scroll.config").options.marks.scope.enabled = true
end)

t.finish("scope")
