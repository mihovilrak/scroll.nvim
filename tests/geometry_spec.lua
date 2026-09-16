-- Run with: nvim -l tests/geometry_spec.lua
package.path = "lua/?.lua;lua/?/init.lua;" .. package.path
local t = dofile("tests/harness.lua")
local geometry = require("scroll.geometry")

t.describe("no bar when content fits", function()
  t.eq(geometry.thumb({ track = 20, total = 20, offset = 0 }), nil, "exactly fits")
  t.eq(geometry.thumb({ track = 20, total = 5, offset = 0 }), nil, "smaller than window")
  t.eq(geometry.thumb({ track = 0, total = 100, offset = 0 }), nil, "zero-length track")
end)

t.describe("thumb is flush at both ends", function()
  local top = geometry.thumb({ track = 20, total = 100, offset = 0 })
  t.eq(top.pos, 0, "at offset 0 the thumb starts at the top")

  -- offset 80 = the last page of a 100-row buffer in a 20-row window
  local bot = geometry.thumb({ track = 20, total = 100, offset = 80 })
  t.eq(bot.pos + bot.size, 20, "on the last page the thumb ends at the track end")

  -- Overscrolling must not push the thumb past the end.
  local over = geometry.thumb({ track = 20, total = 100, offset = 999 })
  t.eq(over.pos + over.size, 20, "offset beyond the end stays clamped")
end)

t.describe("invariants hold across a wide sweep", function()
  for track = 1, 60, 7 do
    for total = 1, 5000, 37 do
      for _, frac in ipairs({ 0, 0.01, 0.33, 0.5, 0.99, 1 }) do
        local offset = math.floor((total - track) * frac)
        local r = geometry.thumb({ track = track, total = total, offset = offset })
        if r then
          local tag = string.format("track=%d total=%d offset=%d", track, total, offset)
          t.check(r.size >= 1, "thumb at least 1 cell: " .. tag)
          t.check(r.size <= track, "thumb fits the track: " .. tag)
          t.check(r.pos >= 0, "thumb not before the track: " .. tag)
          t.check(r.pos + r.size <= track, "thumb not past the track end: " .. tag)
        end
      end
    end
  end
end)

t.describe("monotonicity: scrolling down never moves the thumb up", function()
  local prev = -1
  for offset = 0, 980 do
    local r = geometry.thumb({ track = 25, total = 1000, offset = offset })
    t.check(r.pos >= prev, "thumb position is non-decreasing at offset " .. offset)
    prev = r.pos
  end
end)

t.describe("offset_at inverts thumb", function()
  -- Dragging the thumb to a position and reading back the offset should land
  -- on an offset whose thumb renders at that same position.
  for _, pos in ipairs({ 0, 1, 5, 12, 17 }) do
    local offset = geometry.offset_at({ track = 20, total = 100, pos = pos })
    local r = geometry.thumb({ track = 20, total = 100, offset = offset })
    t.check(math.abs(r.pos - pos) <= 1, string.format("round-trip pos=%d -> offset=%d -> pos=%d", pos, offset, r.pos))
  end
  t.eq(geometry.offset_at({ track = 20, total = 100, pos = 0 }), 0, "top of track is offset 0")
  t.eq(geometry.offset_at({ track = 20, total = 100, pos = 99 }), 80, "bottom of track is the last page")
end)

t.describe("degenerate inputs do not error", function()
  t.eq(geometry.offset_at({ track = 10, total = 5, pos = 3 }), 0, "content fits -> offset 0")
  local r = geometry.thumb({ track = 3, total = 100000, offset = 50000 })
  t.check(r.size == 1, "huge buffer in a tiny track still yields a 1-cell thumb")
end)

t.finish("geometry")
