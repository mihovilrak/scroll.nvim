--- Git change marks for the overview ruler.
---
--- Hunks come from gitsigns whenever it is attached to the buffer. Without it,
--- the buffer is diffed against the index ourselves: the index copy is fetched
--- once with `git show` (asynchronously), then `vim.diff` compares it with the
--- live buffer text, so unsaved edits are marked too.
---
--- That diff is O(lines) -- probed at ~140ms for 100k lines including joining
--- the buffer -- so it is debounced after edits and skipped above
--- `marks.git.max_lines`.
local config = require("scroll.config")

local M = {}

local diff = vim.text and vim.text.diff or vim.diff

--- @class scroll.GitEntry
--- @field version integer
--- @field ranges table[]
--- @field base string|false|nil  index text; false = not tracked; nil = unknown
--- @field generation integer     bumped to discard stale `git show` replies
--- @field fetching boolean
--- @field tick integer?          changedtick the ranges were computed at
--- @field pending integer?       changedtick a debounced diff is waiting for
--- @field timer userdata?

--- @type table<integer, scroll.GitEntry>
local cache = {}
local counter = 0

local function stop_timer(entry)
  if entry.timer then
    entry.timer:stop()
    if not entry.timer:is_closing() then
      entry.timer:close()
    end
    entry.timer = nil
  end
  entry.pending = nil
end

local function publish(entry, ranges)
  counter = counter + 1
  entry.ranges, entry.version = ranges, counter
end

local function entry_for(buf)
  local entry = cache[buf]
  if not entry then
    entry = { version = 0, ranges = {}, generation = 0, fetching = false }
    cache[buf] = entry
  end
  return entry
end

local function range(first, count, kind)
  if count == 0 then
    -- A deletion sits between lines; mark the line above it (or the first
    -- line, when the deletion is at the very top).
    first = math.max(first, 1)
    return { first = first, last = first, kind = kind }
  end
  return { first = first, last = first + count - 1, kind = kind }
end

--- @return table[]|nil  nil when gitsigns is not managing `buf`
local function from_gitsigns(buf)
  local gitsigns = package.loaded.gitsigns
  if not gitsigns or not vim.b[buf].gitsigns_status_dict then
    return nil
  end
  local ok, hunks = pcall(gitsigns.get_hunks, buf)
  if not ok or not hunks then
    return nil
  end
  local ranges = {}
  for _, h in ipairs(hunks) do
    local kind = h.type == "add" and "add" or h.type == "delete" and "delete" or "change"
    local count = kind == "delete" and 0 or h.added.count
    ranges[#ranges + 1] = range(h.added.start, count, kind)
  end
  return ranges
end

--- Hunks as returned by `vim.diff(..., { result_type = "indices" })`:
--- `{ start_a, count_a, start_b, count_b }`, where `b` is the buffer.
local function from_indices(hunks)
  local ranges = {}
  for _, h in ipairs(hunks) do
    local count_a, start_b, count_b = h[2], h[3], h[4]
    local kind = count_b == 0 and "delete" or count_a == 0 and "add" or "change"
    ranges[#ranges + 1] = range(start_b, count_b, kind)
  end
  return ranges
end

local function buffer_text(buf)
  local lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
  return table.concat(lines, "\n") .. "\n"
end

local function compute(buf, entry)
  local tick = vim.api.nvim_buf_get_changedtick(buf)
  local ok, hunks = pcall(diff, entry.base, buffer_text(buf), { result_type = "indices" })
  entry.tick = tick
  publish(entry, ok and from_indices(hunks) or {})
end

local function fetch_base(buf, entry, on_update)
  local name = vim.api.nvim_buf_get_name(buf)
  if name == "" or vim.bo[buf].buftype ~= "" or vim.fn.filereadable(name) == 0 then
    entry.base = false
    return
  end

  entry.fetching = true
  entry.generation = entry.generation + 1
  local generation = entry.generation
  local cmd = { "git", "-C", vim.fs.dirname(name), "show", ":./" .. vim.fs.basename(name) }
  local ok = pcall(vim.system, cmd, { text = true }, function(result)
    vim.schedule(function()
      if cache[buf] ~= entry or entry.generation ~= generation then
        return
      end
      entry.fetching = false
      if result.code == 0 then
        -- The index may store CRLF while the buffer's lines never carry it.
        entry.base = (result.stdout:gsub("\r\n", "\n"))
      else
        entry.base = false -- not in a repository, or not tracked
        publish(entry, {})
      end
      entry.tick = nil
      if on_update then
        on_update()
      end
    end)
  end)
  if not ok then
    entry.fetching = false
    entry.base = false -- no git executable
  end
end

--- @param buf integer
--- @param on_update function|nil  called when an asynchronous result lands
--- @return table[], integer
function M.get(buf, on_update)
  local entry = entry_for(buf)

  if entry.gitsigns then
    return entry.ranges, entry.version
  end
  local ranges = from_gitsigns(buf)
  if ranges then
    stop_timer(entry)
    entry.gitsigns = true
    publish(entry, ranges)
    return entry.ranges, entry.version
  end

  if entry.base == nil then
    if not entry.fetching then
      fetch_base(buf, entry, on_update)
    end
    return entry.ranges, entry.version
  end
  if entry.base == false then
    return entry.ranges, entry.version
  end

  local opts = config.options.marks.git
  local tick = vim.api.nvim_buf_get_changedtick(buf)
  if entry.tick == tick or vim.api.nvim_buf_line_count(buf) > opts.max_lines then
    return entry.ranges, entry.version
  end

  if entry.tick == nil then
    -- First diff since the index copy arrived: nothing to debounce.
    compute(buf, entry)
    return entry.ranges, entry.version
  end

  if entry.pending ~= tick then
    stop_timer(entry)
    entry.pending = tick
    local timer = vim.uv.new_timer()
    entry.timer = timer
    timer:start(
      opts.debounce,
      0,
      vim.schedule_wrap(function()
        if entry.timer ~= timer then
          return
        end
        stop_timer(entry)
        if cache[buf] ~= entry or not vim.api.nvim_buf_is_valid(buf) then
          return
        end
        compute(buf, entry)
        if on_update then
          on_update()
        end
      end)
    )
  end
  return entry.ranges, entry.version
end

--- gitsigns recomputed its hunks (`User GitSignsUpdate`).
--- @param buf integer
function M.gitsigns_updated(buf)
  local entry = cache[buf]
  if entry then
    entry.gitsigns = nil
  end
end

--- The index may have moved: the file was written, or focus came back from a
--- terminal where `git add` / `git checkout` may have run.
--- @param buf integer
function M.refetch(buf)
  local entry = cache[buf]
  if entry and not entry.gitsigns then
    entry.base = nil
    entry.fetching = false
    entry.generation = entry.generation + 1
  end
end

function M.refetch_all()
  for buf in pairs(cache) do
    M.refetch(buf)
  end
end

--- @param buf integer
function M.forget(buf)
  local entry = cache[buf]
  if entry then
    stop_timer(entry)
    entry.generation = entry.generation + 1
    cache[buf] = nil
  end
end

function M.reset()
  for buf in pairs(cache) do
    M.forget(buf)
  end
  cache = {}
end

return M
