--[[
  The "little light": a light bulb that takes the colour of
  the judgement of your move. Tap it for the coach's opinion.
]]

local Blitbuffer = require("ffi/blitbuffer")
local Geom = require("ui/geometry")
local GestureRange = require("ui/gesturerange")
local InputContainer = require("ui/widget/container/inputcontainer")
local Draw = require("cc_draw")

local Lamp = InputContainer:extend{
    size = 60,
    rgb = nil,     -- fill colour (nil = off)
    gray = 0xFF,
    active = false, -- coach view open
    callback = nil,
}

function Lamp:init()
    self.dimen = Geom:new{ x = 0, y = 0, w = self.size, h = self.size }
    self.ges_events = {
        TapLamp = { GestureRange:new{ ges = "tap", range = function() return self.dimen end } },
    }
end

function Lamp:getSize()
    return Geom:new{ w = self.size, h = self.size }
end

function Lamp:onTapLamp()
    if self.callback then self.callback() end
    return true
end

function Lamp:paintTo(bb, x, y)
    self.dimen.x, self.dimen.y = x, y
    local s = self.size
    local cx = x + math.floor(s / 2)
    local r = math.floor(s * 0.30)
    local cy = y + math.floor(s * 0.08) + r
    local lw = math.max(2, math.floor(s * 0.05))
    if self.active then
        -- subtle halo when the coach view is open
        Draw.disc(bb, cx, cy, r + lw * 2, nil, 0xD8)
    end
    -- bulb glass
    Draw.disc(bb, cx, cy, r, nil, 0x00)
    if self.rgb then
        Draw.disc(bb, cx, cy, r - lw, self.rgb, self.gray)
    else
        Draw.disc(bb, cx, cy, r - lw, nil, 0xFF)
    end
    -- neck and base
    local bw = math.floor(r * 0.9)
    local by = cy + r - lw
    bb:paintRect(cx - math.floor(bw / 2), by, bw, lw * 2, Blitbuffer.COLOR_BLACK)
    bb:paintRect(cx - math.floor(bw / 2) + lw, by + lw * 3, bw - lw * 2, lw, Blitbuffer.COLOR_BLACK)
    bb:paintRect(cx - math.floor(bw / 4), by + lw * 5, math.floor(bw / 2), lw, Blitbuffer.COLOR_BLACK)
end

return Lamp
