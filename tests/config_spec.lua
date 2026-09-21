-- Run with: nvim --headless -u NONE -l tests/config_spec.lua
package.path = "lua/?.lua;lua/?/init.lua;" .. package.path
local t = dofile("tests/harness.lua")

local config = require("scroll.config")

local cases = {
  { "enabled", { enabled = "yes" } },
  { "vertical.enabled", { vertical = { enabled = 1 } } },
  { "vertical.width", { vertical = { width = 0 } } },
  { "vertical.width", { vertical = { width = 1.5 } } },
  { "vertical.char", { vertical = { char = "xx" } } },
  { "vertical.track_char", { vertical = { track_char = "" } } },
  { "horizontal.enabled", { horizontal = { enabled = 1 } } },
  { "horizontal.height", { horizontal = { height = 0 } } },
  { "horizontal.height", { horizontal = { height = 1.5 } } },
  { "horizontal.char", { horizontal = { char = "xx" } } },
  { "horizontal.track_char", { horizontal = { track_char = "xx" } } },
  { "visibility", { visibility = "sometimes" } },
  { "hide_delay", { hide_delay = -1 } },
  { "hide_delay", { hide_delay = 1.5 } },
  { "winblend", { winblend = 101 } },
  { "zindex", { zindex = 0 } },
  { "mouse", { mouse = "yes" } },
  { "min_width", { min_width = 0 } },
  { "min_height", { min_height = 1.5 } },
  { "exact_measure_max_lines", { exact_measure_max_lines = -1 } },
  { "excluded_filetypes", { excluded_filetypes = { "lua", 1 } } },
  { "excluded_buftypes", { excluded_buftypes = "terminal" } },
  { "minimap.enabled", { minimap = { enabled = 1 } } },
  { "minimap.width", { minimap = { width = 2.5 } } },
  { "minimap.columns_per_dot", { minimap = { columns_per_dot = 0 } } },
  { "minimap.colors", { minimap = { colors = 1 } } },
  { "minimap.min_window_width", { minimap = { min_window_width = 0 } } },
  { "minimap.excluded_filetypes", { minimap = { excluded_filetypes = { false } } } },
  { "minimap.enabled_for", { minimap = { enabled_for = true } } },
  { "minimap.cursor", { minimap = { cursor = 1 } } },
  { "minimap.dodge.margin", { minimap = { dodge = { margin = 1 } } } },
  { "minimap.dodge.hide", { minimap = { dodge = { hide = 1 } } } },
  { "minimap.git", { minimap = { git = 1 } } },
  { "minimap.git_char", { minimap = { git_char = "wide" } } },
  { "minimap.winblend", { minimap = { winblend = 2.5 } } },
  { "minimap.autohide", { minimap = { autohide = 1 } } },
  { "explorer.enabled", { explorer = { enabled = 1 } } },
  { "explorer.filetypes", { explorer = { filetypes = { 1 } } } },
  { "explorer.snacks", { explorer = { snacks = 1 } } },
  { "explorer.horizontal", { explorer = { horizontal = 1 } } },
  { "explorer.min_width", { explorer = { min_width = 0 } } },
  { "marks.enabled", { marks = { enabled = 1 } } },
  { "marks.diagnostics.enabled", { marks = { diagnostics = { enabled = 1 } } } },
  { "marks.diagnostics.char", { marks = { diagnostics = { char = "xx" } } } },
  { "marks.diagnostics.severity", { marks = { diagnostics = { severity = false } } } },
  { "marks.git.max_lines", { marks = { git = { max_lines = -1 } } } },
  { "marks.git.debounce", { marks = { git = { debounce = 1.5 } } } },
  { "marks.scope.node_types", { marks = { scope = { node_types = { "if", false } } } } },
}

t.describe("every public option rejects invalid values synchronously", function()
  for _, case in ipairs(cases) do
    config.setup({})
    local ok, err = pcall(config.setup, case[2])
    t.check(not ok, case[1] .. " is rejected")
    t.check(tostring(err):find(case[1], 1, true) ~= nil, case[1] .. " is named in the error")
  end
end)

t.describe("dimensions and cross-field constraints accept valid boundaries", function()
  local opts = config.setup({
    horizontal = { height = 2 },
    minimap = { enabled = true, width = 2, min_window_width = 4 },
    min_width = 4,
    vertical = { width = 1 },
    hide_delay = 0,
    exact_measure_max_lines = 0,
  })
  t.eq(opts.horizontal.height, 2, "multi-row horizontal bars are valid")

  local ok, err = pcall(config.setup, {
    minimap = { enabled = true, width = 3, min_window_width = 4 },
    min_width = 4,
    vertical = { width = 1 },
  })
  t.check(not ok, "a minimap and bar that consume the whole eligible window are rejected")
  t.check(tostring(err):find("minimap.width", 1, true) ~= nil, "the cross-field error names minimap.width")
end)

t.describe("a failed setup leaves the last valid options in place", function()
  local before = config.setup({ min_width = 27 })
  pcall(config.setup, { vertical = { width = 0 } })
  t.eq(config.options, before, "invalid merged options are never published")
  t.eq(config.options.min_width, 27, "the prior values remain intact")
end)

t.finish("config")
