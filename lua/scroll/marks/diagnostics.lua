--- Diagnostic marks for the overview ruler.
---
--- Every mark source returns `ranges, version`: a list of
--- `{ first, last, kind }` (1-based, inclusive buffer lines) and a value that
--- changes whenever the list does, so the ruler can skip re-placing marks.
local config = require("scroll.config")

local M = {}

local KIND = {
  [vim.diagnostic.severity.ERROR] = "error",
  [vim.diagnostic.severity.WARN] = "warn",
  [vim.diagnostic.severity.INFO] = "info",
  [vim.diagnostic.severity.HINT] = "hint",
}

--- @type table<integer, { version: integer, ranges: table[] }>
local cache = {}
local counter = 0

--- Called on `DiagnosticChanged`.
--- @param buf integer
function M.invalidate(buf)
  cache[buf] = nil
end

--- @param buf integer
--- @return table[], integer
function M.get(buf)
  local entry = cache[buf]
  if entry then
    return entry.ranges, entry.version
  end

  local ranges = {}
  if vim.diagnostic.is_enabled({ bufnr = buf }) then
    local opts = { severity = config.options.marks.diagnostics.severity }
    for _, d in ipairs(vim.diagnostic.get(buf, opts)) do
      -- Only the first line: a multi-line diagnostic is still one problem,
      -- and marking its whole span would drown out everything around it.
      ranges[#ranges + 1] = { first = d.lnum + 1, last = d.lnum + 1, kind = KIND[d.severity] or "hint" }
    end
  end

  counter = counter + 1
  cache[buf] = { version = counter, ranges = ranges }
  return ranges, counter
end

--- @param buf integer
function M.forget(buf)
  cache[buf] = nil
end

function M.reset()
  cache = {}
end

return M
