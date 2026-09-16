--- When the bars are on screen.
---
---   always  drawn whenever the content overflows
---   auto    drawn on activity, hidden after `hide_delay` ms of quiet
---   hover   drawn only while the pointer is over the bar region
local config = require("scroll.config")
local render = require("scroll.render")

local M = {}

--- @type userland|nil
local timer = nil

local function cancel()
  if timer then
    timer:stop()
    if not timer:is_closing() then
      timer:close()
    end
    timer = nil
  end
end

--- Something happened that the bars should reflect.
function M.on_activity()
  local mode = config.options.visibility

  if mode == "hover" then
    -- Position is driven entirely by the pointer; redraw but stay hidden
    -- unless the mouse module says otherwise.
    render.refresh_all()
    if not render.hover.win then
      render.hide_all()
    end
    return
  end

  render.refresh_all()

  if mode == "auto" then
    cancel()
    timer = vim.uv.new_timer()
    timer:start(
      config.options.hide_delay,
      0,
      vim.schedule_wrap(function()
        cancel()
        -- Keep the bar up while the pointer rests on it, so it does not
        -- vanish from under a click.
        if not render.hover.win then
          render.hide_all()
        end
      end)
    )
  end
end

function M.stop()
  cancel()
end

return M
