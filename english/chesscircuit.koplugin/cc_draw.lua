--[[
  Small drawing helpers: pastel colours (with a grey fallback
  on black and white screens), thick lines, arrows, discs, glyphs.
]]

local Blitbuffer = require("ffi/blitbuffer")
local Device = require("device")
local Font = require("ui/font")
local RenderText = require("ui/rendertext")
local Screen = Device.screen

local Draw = {}

function Draw.colorEnabled()
    return Screen.isColorEnabled and Screen:isColorEnabled() or false
end

-- rgb = {r, g, b}, gray = 0..255 value used on black and white screens
function Draw.rect(bb, x, y, w, h, rgb, gray)
    if w <= 0 or h <= 0 then return end
    if rgb and Draw.colorEnabled() and bb.paintRectRGB32 then
        bb:paintRectRGB32(x, y, w, h, Blitbuffer.ColorRGB32(rgb[1], rgb[2], rgb[3], 0xFF))
    else
        bb:paintRect(x, y, w, h, Blitbuffer.Color8(gray or 0x80))
    end
end

function Draw.roundedRect(bb, x, y, w, h, r, rgb, gray)
    if rgb and Draw.colorEnabled() and bb.paintRoundedRectRGB32 then
        bb:paintRoundedRectRGB32(x, y, w, h, Blitbuffer.ColorRGB32(rgb[1], rgb[2], rgb[3], 0xFF), r)
    else
        bb:paintRoundedRect(x, y, w, h, Blitbuffer.Color8(gray or 0x80), r)
    end
end

-- Filled disc (drawn line by line so it can take colour)
function Draw.disc(bb, cx, cy, r, rgb, gray)
    for dy = -r, r do
        local half = math.floor(math.sqrt(r * r - dy * dy) + 0.5)
        Draw.rect(bb, cx - half, cy + dy, 2 * half + 1, 1, rgb, gray)
    end
end

-- Thick line
function Draw.line(bb, x0, y0, x1, y1, th, rgb, gray)
    local dx, dy = x1 - x0, y1 - y0
    local len = math.sqrt(dx * dx + dy * dy)
    local step = math.max(1, th / 3)
    local n = math.max(1, math.floor(len / step))
    local half = math.floor(th / 2)
    for i = 0, n do
        local t = i / n
        local x = math.floor(x0 + dx * t + 0.5)
        local y = math.floor(y0 + dy * t + 0.5)
        Draw.rect(bb, x - half, y - half, th, th, rgb, gray)
    end
end

-- Arrow from one square to another (centre coordinates)
function Draw.arrow(bb, x0, y0, x1, y1, sq, rgb, gray)
    local dx, dy = x1 - x0, y1 - y0
    local len = math.sqrt(dx * dx + dy * dy)
    if len < 1 then return end
    local ux, uy = dx / len, dy / len
    -- start a little after the centre of the start square
    local sx, sy = x0 + ux * sq * 0.22, y0 + uy * sq * 0.22
    -- tip a little before the centre of the target square
    local tx, ty = x1 - ux * sq * 0.12, y1 - uy * sq * 0.12
    local head = sq * 0.42
    local hw = sq * 0.26
    local bx, by = tx - ux * head, ty - uy * head
    local th = math.max(3, math.floor(sq * 0.14))
    -- thin dark outline for readability, then the colour
    Draw.line(bb, sx, sy, bx, by, th + 4, nil, 0x40)
    Draw.line(bb, sx, sy, bx, by, th, rgb, gray)
    local px, py = -uy, ux
    local function fillTri(ax, ay, p1x, p1y, p2x, p2y, c_rgb, c_gray)
        local ddx, ddy = p2x - p1x, p2y - p1y
        local n = math.max(1, math.ceil(math.sqrt(ddx * ddx + ddy * ddy)))
        for k = 0, n do
            local f = k / n
            Draw.line(bb, ax, ay, p1x + ddx * f, p1y + ddy * f, 2, c_rgb, c_gray)
        end
    end
    -- dark outline (slightly larger triangle), then the coloured tip
    local o = 3
    fillTri(tx + ux * o, ty + uy * o,
        bx + px * (hw + o) - ux * o, by + py * (hw + o) - uy * o,
        bx - px * (hw + o) - ux * o, by - py * (hw + o) - uy * o, nil, 0x40)
    fillTri(tx, ty, bx + px * hw, by + py * hw, bx - px * hw, by - py * hw, rgb, gray)
end

-- Font size (in KOReader points) to get `px` pixels
function Draw.faceForPixels(name, px)
    local scale = Screen:scaleBySize(1000) / 1000
    local size = math.max(6, math.floor(px / scale + 0.5))
    return Font:getFace(name, size)
end

-- Draws a character centred on (cx, cy)
function Draw.glyphCentered(bb, face, codepoint, cx, cy, color, refcode)
    local ref = RenderText:getGlyph(face, refcode or codepoint)
    local g = (refcode and refcode ~= codepoint) and RenderText:getGlyph(face, codepoint) or ref
    local rw, rh = ref.bb:getWidth(), ref.bb:getHeight()
    local penx = math.floor(cx - (ref.l + rw / 2) + 0.5)
    local baseline = math.floor(cy + (ref.t - rh / 2) + 0.5)
    bb:colorblitFrom(g.bb, penx + g.l, baseline - g.t, 0, 0, g.bb:getWidth(), g.bb:getHeight(), color)
end

-- Centred text (may contain several characters)
function Draw.textCentered(bb, face, text, cx, cy, color, bold)
    local size = RenderText:sizeUtf8Text(0, 10000, face, text, true, bold)
    local x = math.floor(cx - size.x / 2 + 0.5)
    local baseline = math.floor(cy + (size.y_top - size.y_bottom) / 2 + 0.5)
    RenderText:renderUtf8Text(bb, x, baseline, face, text, true, bold, color or Blitbuffer.COLOR_BLACK)
end

-- Filled polygon (points = { {x, y}, ... }), scanline fill
function Draw.polygon(bb, pts, rgb, gray)
    local miny, maxy = math.huge, -math.huge
    for _, p in ipairs(pts) do
        if p[2] < miny then miny = p[2] end
        if p[2] > maxy then maxy = p[2] end
    end
    miny, maxy = math.floor(miny), math.ceil(maxy)
    local n = #pts
    for y = miny, maxy do
        local yy = y + 0.5
        local xs = {}
        for i = 1, n do
            local a, b = pts[i], pts[i % n + 1]
            if (a[2] <= yy and b[2] > yy) or (b[2] <= yy and a[2] > yy) then
                xs[#xs + 1] = a[1] + (yy - a[2]) * (b[1] - a[1]) / (b[2] - a[2])
            end
        end
        table.sort(xs)
        for k = 1, #xs - 1, 2 do
            local x0 = math.floor(xs[k] + 0.5)
            local x1 = math.floor(xs[k + 1] + 0.5)
            if x1 > x0 then Draw.rect(bb, x0, y, x1 - x0, 1, rgb, gray) end
        end
    end
end

-- Circle (outline only)
function Draw.ring(bb, cx, cy, r, th, rgb, gray)
    for dy = -r, r do
        local outer = math.sqrt(math.max(0, r * r - dy * dy))
        local ri = r - th
        local inner = (math.abs(dy) < ri) and math.sqrt(ri * ri - dy * dy) or -1
        local x0 = math.floor(cx - outer + 0.5)
        local x1 = math.floor(cx + outer + 0.5)
        if inner < 0 then
            Draw.rect(bb, x0, cy + dy, x1 - x0 + 1, 1, rgb, gray)
        else
            local i0 = math.floor(cx - inner + 0.5)
            local i1 = math.floor(cx + inner + 0.5)
            Draw.rect(bb, x0, cy + dy, i0 - x0, 1, rgb, gray)
            Draw.rect(bb, i1, cy + dy, x1 - i1 + 1, 1, rgb, gray)
        end
    end
end

-- Rectangle outline
function Draw.frame(bb, x, y, w, h, th, rgb, gray)
    Draw.rect(bb, x, y, w, th, rgb, gray)
    Draw.rect(bb, x, y + h - th, w, th, rgb, gray)
    Draw.rect(bb, x, y, th, h, rgb, gray)
    Draw.rect(bb, x + w - th, y, th, h, rgb, gray)
end

return Draw
