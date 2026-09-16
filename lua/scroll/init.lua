--- scroll.nvim -- vertical and horizontal scrollbars.
local config = require("scroll.config")
local events = require("scroll.events")
local highlight = require("scroll.highlight")
local mouse = require("scroll.mouse")
local render = require("scroll.render")

local M = {}

local active = false

--- @param opts table|nil
function M.setup(opts)
  config.setup(opts)
  highlight.setup()

  if config.options.enabled == false then
    return
  end
  M.enable()
end

function M.enable()
  if active then
    return
  end
  active = true

  events.enable()
  if config.options.mouse then
    mouse.enable()
  end
  events.schedule()
end

function M.disable()
  if not active then
    return
  end
  active = false

  mouse.disable()
  events.disable()
end

function M.toggle()
  if active then
    M.disable()
  else
    M.enable()
  end
end

--- Redraw the bars now, bypassing the coalescer. Mostly useful from tests and
--- from a user's own autocmds.
function M.refresh()
  if active then
    render.refresh_all()
  end
end

function M.is_enabled()
  return active
end

return M
