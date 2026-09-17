--- Scope marks for the overview ruler: where the code block around the cursor
--- (a function, an `if`, a loop, ...) starts and ends.
---
--- Found from the trees the treesitter highlighter already keeps, so this
--- never parses anything itself; buffers without treesitter highlighting get
--- no scope marks. Only the current window shows them.
local config = require("scroll.config")

local M = {}

--- Words in a node type that make it not a scope even when another word
--- matches: `function_call`, `method_invocation`, `formal_parameters`, ...
local IGNORE = { call = true, invocation = true, arguments = true, parameters = true, parameter = true }

--- @type table<string, boolean>
local is_scope = {}
--- @type table|nil  the `node_types` list `is_scope` was built from
local built_from = nil

--- Whether a node of type `type` is a scope.
--- @param type string
--- @return boolean
local function matches(type)
  local words = config.options.marks.scope.node_types
  if built_from ~= words then
    built_from, is_scope = words, {}
  end
  local cached = is_scope[type]
  if cached ~= nil then
    return cached
  end
  local wanted, found = {}, false
  for _, w in ipairs(words) do
    wanted[w] = true
  end
  for word in type:gmatch("[^_]+") do
    if IGNORE[word] then
      found = false
      break
    end
    found = found or wanted[word] == true
  end
  is_scope[type] = found
  return found
end

--- The 0-based start and end rows of the scope around (`row`, `col`), or nil.
--- @param buf integer
--- @param row integer  0-based
--- @param col integer  0-based byte column
--- @return integer|nil, integer|nil
function M.find(buf, row, col)
  local highlighter = vim.treesitter.highlighter.active[buf]
  local parser = highlighter and highlighter.tree
  if not parser or #parser:trees() == 0 then
    return nil, nil
  end
  local node = parser:named_node_for_range({ row, col, row, col }, { ignore_injections = false })
  while node do
    local sr, _, er, ec = node:range()
    -- A node ending at column 0 really ends on the line before.
    if ec == 0 and er > sr then
      er = er - 1
    end
    if er > sr and matches(node:type()) then
      return sr, er
    end
    node = node:parent()
  end
  return nil, nil
end

--- @param buf integer
--- @param _ function|nil  unused: the source is synchronous
--- @param win integer|nil  the window whose cursor to follow
--- @return table[], string
function M.get(buf, _, win)
  if not win or win ~= vim.api.nvim_get_current_win() then
    return {}, "none"
  end
  local cursor = vim.api.nvim_win_get_cursor(win)
  local row = cursor[1] - 1
  -- From the start of the text: on an `if` line with the cursor still in the
  -- indent, the `if` is the scope, not the block around it.
  local line = vim.api.nvim_buf_get_lines(buf, row, row + 1, false)[1] or ""
  local col = math.max(cursor[2], (line:find("%S") or 1) - 1)
  local ok, first, last = pcall(M.find, buf, row, col)
  if not ok or not first then
    return {}, "none"
  end
  return {
    { first = first + 1, last = first + 1, kind = "scope" },
    { first = last + 1, last = last + 1, kind = "scope" },
  }, first .. "-" .. last
end

function M.forget(_) end

function M.reset()
  is_scope, built_from = {}, nil
end

return M
