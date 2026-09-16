--- scroll.nvim -- vertical and horizontal scrollbars.
local config = require("scroll.config")
local events = require("scroll.events")
local highlight = require("scroll.highlight")
local mouse = require("scroll.mouse")
local render = require("scroll.render")

local M = {}

local active = false

--- Whether `setup` has run, so the automatic setup in `plugin/scroll.lua`
--- can stand aside for a user's own call.
M.did_setup = false

--- Optional: the plugin sets itself up with the defaults at startup. Call this
--- to change options; calling it again replaces them.
--- @param opts table|nil
function M.setup(opts)
  M.did_setup = true
  config.setup(opts)
  highlight.setup()

  -- Restart, so options read at enable time (`mouse`) take effect and every
  -- bar is redrawn from the new options.
  M.disable()
  if config.options.enabled ~= false then
    M.enable()
  end
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
    highlight.setup()
    render.refresh_all()
  end
end

--- Show or hide the minimap in every window.
--- @param on boolean|nil  force a state instead of toggling
function M.toggle_minimap(on)
  local mm = config.options.minimap
  if on == nil then
    on = not mm.enabled
  end
  mm.enabled = on
  if active then
    render.refresh_all()
  end
end

function M.is_enabled()
  return active
end

return M
