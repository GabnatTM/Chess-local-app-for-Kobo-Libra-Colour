--[[
  Small drawings: landmarks of the 10 capitals, trophies, ticket,
  crown and menu icons. Everything is drawn with simple shapes.
]]

local Draw = require("cc_draw")

local Art = {}

local function R(bb, x, y, w, h, g) Draw.rect(bb, math.floor(x), math.floor(y), math.ceil(w), math.ceil(h), nil, g) end
local function P(bb, pts, g) Draw.polygon(bb, pts, nil, g) end
local function D(bb, cx, cy, r, g) Draw.disc(bb, math.floor(cx), math.floor(cy), math.max(1, math.floor(r)), nil, g) end

---------------------------------------------------------------------------
-- Landmarks (silhouettes) in the box (x, y, w, h), standing on the bottom
---------------------------------------------------------------------------

local B = {}

B.atomium = function(bb, x, y, w, h, g)
    local cx, s = x + w / 2, math.min(w, h)
    local r = s * 0.075
    local top, bot = y + h * 0.12, y + h * 0.72
    local pts = {
        { cx, top }, { cx - s * 0.26, top + (bot - top) * 0.28 }, { cx + s * 0.26, top + (bot - top) * 0.28 },
        { cx, (top + bot) / 2 }, { cx - s * 0.26, top + (bot - top) * 0.72 }, { cx + s * 0.26, top + (bot - top) * 0.72 },
        { cx, bot }, { cx - s * 0.12, top + (bot - top) * 0.5 }, { cx + s * 0.12, top + (bot - top) * 0.5 },
    }
    local links = { {1,2},{1,3},{2,4},{3,4},{2,5},{3,6},{5,7},{6,7},{4,7},{1,4},{8,4},{9,4},{2,8},{3,9},{5,8},{6,9} }
    local th = math.max(2, math.floor(s * 0.025))
    for _, l in ipairs(links) do
        local a, b = pts[l[1]], pts[l[2]]
        Draw.line(bb, a[1], a[2], b[1], b[2], th, nil, g)
    end
    -- legs
    Draw.line(bb, pts[7][1], pts[7][2], cx - s * 0.2, y + h, th, nil, g)
    Draw.line(bb, pts[7][1], pts[7][2], cx + s * 0.2, y + h, th, nil, g)
    Draw.line(bb, pts[7][1], pts[7][2], cx, y + h, th, nil, g)
    for _, p in ipairs(pts) do D(bb, p[1], p[2], r, g) end
    -- highlight
    for _, p in ipairs(pts) do D(bb, p[1] - r * 0.3, p[2] - r * 0.3, r * 0.3, 0xFF) end
end

B.eiffel = function(bb, x, y, w, h, g)
    local cx = x + w / 2
    local bw = math.min(w * 0.8, h * 0.62)
    local top = y + h * 0.02
    P(bb, { { cx - bw * 0.5, y + h }, { cx - bw * 0.08, y + h * 0.35 }, { cx - bw * 0.03, top + h * 0.06 },
        { cx, top }, { cx + bw * 0.03, top + h * 0.06 }, { cx + bw * 0.08, y + h * 0.35 }, { cx + bw * 0.5, y + h } }, g)
    -- arch
    P(bb, { { cx - bw * 0.3, y + h + 1 }, { cx - bw * 0.22, y + h * 0.84 }, { cx, y + h * 0.78 },
        { cx + bw * 0.22, y + h * 0.84 }, { cx + bw * 0.3, y + h + 1 } }, 0xFF)
    -- platforms
    R(bb, cx - bw * 0.3, y + h * 0.66, bw * 0.6, h * 0.035, g)
    R(bb, cx - bw * 0.14, y + h * 0.36, bw * 0.28, h * 0.03, g)
end

B.bigben = function(bb, x, y, w, h, g)
    local cx = x + w / 2
    local tw = math.min(w * 0.3, h * 0.2)
    R(bb, cx - tw / 2, y + h * 0.32, tw, h * 0.68, g)
    R(bb, cx - tw * 0.6, y + h * 0.3, tw * 1.2, h * 0.24, g)
    P(bb, { { cx - tw * 0.6, y + h * 0.3 }, { cx, y + h * 0.04 }, { cx + tw * 0.6, y + h * 0.3 } }, g)
    R(bb, cx - 1, y, 3, h * 0.06, g)
    D(bb, cx, y + h * 0.42, tw * 0.42, 0xFF)
    D(bb, cx, y + h * 0.42, tw * 0.08, g)
    Draw.line(bb, cx, y + h * 0.42, cx, y + h * 0.36, math.max(1, tw * 0.06), nil, g)
    Draw.line(bb, cx, y + h * 0.42, cx + tw * 0.2, y + h * 0.42, math.max(1, tw * 0.06), nil, g)
    -- windows
    for i = 0, 3 do R(bb, cx - tw * 0.15, y + h * (0.6 + i * 0.09), tw * 0.3, h * 0.04, 0xFF) end
    -- parliament building next to it
    R(bb, cx + tw / 2, y + h * 0.78, w * 0.32, h * 0.22, g)
    for i = 0, 3 do R(bb, cx + tw / 2 + w * 0.03 + i * w * 0.075, y + h * 0.74, w * 0.035, h * 0.05, g) end
end

B.alcala = function(bb, x, y, w, h, g)
    local gw = math.min(w * 0.92, h * 1.3)
    local gx = x + (w - gw) / 2
    local top = y + h * 0.4
    R(bb, gx, top, gw, h - (top - y), g)
    -- pediment
    P(bb, { { gx + gw * 0.3, top }, { gx + gw * 0.5, top - h * 0.2 }, { gx + gw * 0.7, top } }, g)
    R(bb, gx + gw * 0.03, top - h * 0.04, gw * 0.94, h * 0.05, g)
    -- arches
    local function arch(ax, aw, ah)
        R(bb, ax, y + h - ah + aw / 2, aw, ah - aw / 2 + 1, 0xFF)
        D(bb, ax + aw / 2, y + h - ah + aw / 2, aw / 2, 0xFF)
    end
    arch(gx + gw * 0.42, gw * 0.16, h * 0.42)
    arch(gx + gw * 0.2, gw * 0.12, h * 0.34)
    arch(gx + gw * 0.68, gw * 0.12, h * 0.34)
    arch(gx + gw * 0.05, gw * 0.08, h * 0.22)
    arch(gx + gw * 0.87, gw * 0.08, h * 0.22)
end

B.colisee = function(bb, x, y, w, h, g)
    local cw = math.min(w * 0.95, h * 1.45)
    local cx0 = x + (w - cw) / 2
    local top = y + h * 0.25
    -- shape: right side higher (ruin)
    P(bb, { { cx0, y + h }, { cx0, top + h * 0.22 }, { cx0 + cw * 0.5, top + h * 0.1 }, { cx0 + cw * 0.75, top },
        { cx0 + cw, top + h * 0.05 }, { cx0 + cw, y + h } }, g)
    -- rows of arches
    local rows = 3
    for rIdx = 0, rows - 1 do
        local ry = y + h - (rIdx + 1) * h * 0.2
        local n = 7
        for i = 0, n - 1 do
            local ax = cx0 + cw * (0.05 + i * 0.13)
            local aw = cw * 0.07
            local limitTop = (ax < cx0 + cw * 0.5) and (top + h * 0.22) or top
            if ry - h * 0.02 > limitTop + h * 0.04 then
                R(bb, ax, ry + aw / 2, aw, h * 0.13 - aw / 2, 0xFF)
                D(bb, ax + aw / 2, ry + aw / 2, aw / 2, 0xFF)
            end
        end
    end
end

B.brandebourg = function(bb, x, y, w, h, g)
    local gw = math.min(w * 0.95, h * 1.25)
    local gx = x + (w - gw) / 2
    local top = y + h * 0.38
    R(bb, gx, top, gw, h * 0.12, g)
    R(bb, gx + gw * 0.25, top - h * 0.08, gw * 0.5, h * 0.09, g)
    -- quadriga
    R(bb, gx + gw * 0.42, top - h * 0.24, gw * 0.16, h * 0.16, g)
    D(bb, gx + gw * 0.5, top - h * 0.27, gw * 0.05, g)
    -- columns
    local n = 6
    for i = 0, n - 1 do
        local px = gx + gw * (0.02 + i * 0.188)
        R(bb, px, top + h * 0.12, gw * 0.06, h * 0.5, g)
    end
    R(bb, gx, y + h * 0.94, gw, h * 0.06, g)
end

B.parlement = function(bb, x, y, w, h, g)
    local pw = math.min(w * 0.96, h * 1.6)
    local px = x + (w - pw) / 2
    local base = y + h * 0.55
    R(bb, px, base, pw, h - (base - y), g)
    -- central dome
    D(bb, px + pw / 2, base, pw * 0.15, g)
    R(bb, px + pw * 0.38, base - h * 0.02, pw * 0.24, h * 0.05, g)
    P(bb, { { px + pw * 0.47, base - pw * 0.13 }, { px + pw * 0.5, y + h * 0.05 }, { px + pw * 0.53, base - pw * 0.13 } }, g)
    -- spires
    for _, f in ipairs({ 0.08, 0.22, 0.78, 0.92 }) do
        P(bb, { { px + pw * (f - 0.025), base }, { px + pw * f, base - h * 0.2 }, { px + pw * (f + 0.025), base } }, g)
    end
    -- windows
    for i = 0, 13 do R(bb, px + pw * (0.04 + i * 0.068), base + h * 0.12, pw * 0.025, h * 0.12, 0xFF) end
    R(bb, px - w * 0.02, y + h - 2, pw + w * 0.04, 2, g)
end

B.eglise = function(bb, x, y, w, h, g)
    local cx = x + w / 2
    local s = math.min(w * 0.9, h * 0.9)
    -- steps on both sides (basalt columns)
    local steps = 6
    for i = 0, steps - 1 do
        local sh = h * (0.18 + i * 0.09)
        local sw = s * 0.06
        R(bb, cx - s * 0.08 - (steps - i) * sw, y + h - sh, sw, sh, g)
        R(bb, cx + s * 0.08 + (steps - i - 1) * sw, y + h - sh, sw, sh, g)
    end
    -- central tower
    R(bb, cx - s * 0.08, y + h * 0.18, s * 0.16, h * 0.82, g)
    P(bb, { { cx - s * 0.08, y + h * 0.18 }, { cx, y }, { cx + s * 0.08, y + h * 0.18 } }, g)
    R(bb, cx - s * 0.025, y + h * 0.3, s * 0.05, h * 0.07, 0xFF)
    -- nave
    R(bb, cx - s * 0.5, y + h * 0.82, s, h * 0.18, g)
end

B.obelisque = function(bb, x, y, w, h, g)
    local cx = x + w / 2
    local bw = math.min(w * 0.14, h * 0.09)
    P(bb, { { cx - bw / 2, y + h }, { cx - bw * 0.35, y + h * 0.1 }, { cx, y }, { cx + bw * 0.35, y + h * 0.1 }, { cx + bw / 2, y + h } }, g)
    R(bb, cx - bw * 0.12, y + h * 0.16, bw * 0.24, h * 0.04, 0xFF)
    -- avenue
    R(bb, x + w * 0.05, y + h - h * 0.04, w * 0.9, h * 0.04, g)
    for i = 0, 3 do
        local tx = x + w * (0.1 + i * 0.12)
        if i >= 2 then tx = x + w * (0.62 + (i - 2) * 0.16) end
        D(bb, tx, y + h * 0.84, w * 0.045, g)
        R(bb, tx - 1, y + h * 0.84, 3, h * 0.13, g)
    end
end

B.pagode = function(bb, x, y, w, h, g)
    local cx = x + w / 2
    local s = math.min(w, h * 0.95)
    local tiers = 5
    local tierH = h * 0.15
    for i = 0, tiers - 1 do
        local ty = y + h - (i + 1) * tierH - h * 0.04
        local rw = s * (0.62 - i * 0.08)
        -- curved roof
        P(bb, { { cx - rw / 2 - s * 0.05, ty + tierH * 0.42 }, { cx - rw * 0.3, ty + tierH * 0.12 }, { cx + rw * 0.3, ty + tierH * 0.12 },
            { cx + rw / 2 + s * 0.05, ty + tierH * 0.42 }, { cx + rw * 0.35, ty + tierH * 0.32 }, { cx - rw * 0.35, ty + tierH * 0.32 } }, g)
        R(bb, cx - rw * 0.3, ty + tierH * 0.32, rw * 0.6, tierH * 0.7, g)
        R(bb, cx - rw * 0.08, ty + tierH * 0.5, rw * 0.16, tierH * 0.4, 0xFF)
    end
    local topY = y + h - tiers * tierH - h * 0.04
    R(bb, cx - 1, topY - h * 0.12, 3, h * 0.14, g)
    R(bb, cx - s * 0.36, y + h - h * 0.04, s * 0.72, h * 0.04, g)
end

function Art.building(bb, kind, x, y, w, h, gray)
    local f = B[kind]
    if f then f(bb, x, y, w, h, gray or 0x22) end
end

---------------------------------------------------------------------------
-- Trophies and awards
---------------------------------------------------------------------------

-- Cup: rgb (pastel gold) or outline only if empty
function Art.trophy(bb, x, y, w, h, rgb, empty)
    local cx = x + w / 2
    local cw = math.min(w * 0.7, h * 0.6)
    local outline = empty and 0xC8 or 0x33
    local fillGray = empty and 0xFF or 0xC8
    local fill = (not empty) and rgb or nil
    local function shape(dx, g, colr)
        -- handles
        Draw.ring(bb, math.floor(cx - cw * 0.48), math.floor(y + h * 0.26), math.floor(cw * 0.17 + dx), math.max(2, math.floor(cw * 0.07)), colr, g)
        Draw.ring(bb, math.floor(cx + cw * 0.48), math.floor(y + h * 0.26), math.floor(cw * 0.17 + dx), math.max(2, math.floor(cw * 0.07)), colr, g)
    end
    shape(0, outline, nil)
    -- bowl (outline then fill)
    local function cup(d, g, colr)
        Draw.polygon(bb, {
            { cx - cw / 2 - d, y + h * 0.08 - d }, { cx + cw / 2 + d, y + h * 0.08 - d },
            { cx + cw * 0.42 + d, y + h * 0.32 }, { cx + cw * 0.18 + d, y + h * 0.5 + d },
            { cx - cw * 0.18 - d, y + h * 0.5 + d }, { cx - cw * 0.42 - d, y + h * 0.32 },
        }, colr, g)
    end
    local t = math.max(2, math.floor(cw * 0.04))
    cup(t, outline, nil)
    cup(0, fillGray, fill)
    -- stem
    Draw.rect(bb, math.floor(cx - cw * 0.07), math.floor(y + h * 0.5), math.ceil(cw * 0.14), math.ceil(h * 0.22), fill, empty and outline or fillGray)
    Draw.frame(bb, math.floor(cx - cw * 0.07), math.floor(y + h * 0.5), math.ceil(cw * 0.14), math.ceil(h * 0.22), math.max(1, t - 1), nil, outline)
    -- base
    Draw.rect(bb, math.floor(cx - cw * 0.32), math.floor(y + h * 0.72), math.ceil(cw * 0.64), math.ceil(h * 0.1), fill, fillGray)
    Draw.frame(bb, math.floor(cx - cw * 0.32), math.floor(y + h * 0.72), math.ceil(cw * 0.64), math.ceil(h * 0.1), t, nil, outline)
    Draw.rect(bb, math.floor(cx - cw * 0.42), math.floor(y + h * 0.82), math.ceil(cw * 0.84), math.ceil(h * 0.14), nil, empty and 0xE0 or 0x33)
    if not empty then
        -- highlight
        Draw.rect(bb, math.floor(cx - cw * 0.3), math.floor(y + h * 0.12), math.max(2, math.floor(cw * 0.06)), math.floor(h * 0.18), nil, 0xFF)
    end
end

function Art.ticket(bb, x, y, w, h, rgb, empty)
    local g = empty and 0xC8 or 0x33
    Draw.roundedRect(bb, math.floor(x), math.floor(y + h * 0.25), math.floor(w), math.floor(h * 0.5), math.floor(h * 0.06), nil, g)
    Draw.roundedRect(bb, math.floor(x + 3), math.floor(y + h * 0.25 + 3), math.floor(w - 6), math.floor(h * 0.5 - 6),
        math.floor(h * 0.05), (not empty) and rgb or nil, empty and 0xFF or 0xD8)
    -- notches
    D(bb, x, y + h * 0.5, h * 0.08, 0xFF)
    D(bb, x + w, y + h * 0.5, h * 0.08, 0xFF)
    for i = 0, 5 do R(bb, x + w * 0.72, y + h * (0.3 + i * 0.07), 2, h * 0.035, g) end
end

function Art.crown(bb, x, y, w, h, rgb, empty)
    local g = empty and 0xC8 or 0x33
    local pts = {
        { x + w * 0.1, y + h * 0.8 }, { x + w * 0.05, y + h * 0.3 }, { x + w * 0.3, y + h * 0.55 },
        { x + w * 0.5, y + h * 0.15 }, { x + w * 0.7, y + h * 0.55 }, { x + w * 0.95, y + h * 0.3 }, { x + w * 0.9, y + h * 0.8 },
    }
    Draw.polygon(bb, pts, (not empty) and rgb or nil, empty and 0xFF or 0xD8)
    local th = math.max(2, math.floor(w * 0.035))
    for i = 1, #pts do
        local a, b = pts[i], pts[i % #pts + 1]
        Draw.line(bb, a[1], a[2], b[1], b[2], th, nil, g)
    end
    Draw.rect(bb, math.floor(x + w * 0.1), math.floor(y + h * 0.8), math.ceil(w * 0.8), math.ceil(h * 0.12), nil, g)
    for _, f in ipairs({ 0.05, 0.5, 0.95 }) do
        D(bb, x + w * f, y + h * (f == 0.5 and 0.13 or 0.28), h * 0.07, g)
    end
end

---------------------------------------------------------------------------
-- Menu icons
---------------------------------------------------------------------------

function Art.iconBulb(bb, x, y, s)
    local cx, r = x + s / 2, s * 0.3
    D(bb, cx, y + s * 0.38, r, 0x22)
    D(bb, cx, y + s * 0.38, r - math.max(2, s * 0.06), 0xFF)
    R(bb, cx - r * 0.5, y + s * 0.66, r, s * 0.08, 0x22)
    R(bb, cx - r * 0.4, y + s * 0.78, r * 0.8, s * 0.06, 0x22)
end

function Art.iconClock(bb, x, y, s)
    local cx, cy, r = x + s / 2, y + s / 2, s * 0.4
    Draw.ring(bb, math.floor(cx), math.floor(cy), math.floor(r), math.max(2, math.floor(s * 0.07)), nil, 0x22)
    Draw.line(bb, cx, cy, cx, cy - r * 0.6, math.max(2, s * 0.06), nil, 0x22)
    Draw.line(bb, cx, cy, cx + r * 0.45, cy + r * 0.2, math.max(2, s * 0.06), nil, 0x22)
end

function Art.iconChart(bb, x, y, s)
    local th = math.max(2, s * 0.06)
    R(bb, x + s * 0.1, y + s * 0.85, s * 0.8, th, 0x22)
    local pts = { { 0.12, 0.7 }, { 0.35, 0.5 }, { 0.55, 0.6 }, { 0.85, 0.2 } }
    for i = 1, #pts - 1 do
        Draw.line(bb, x + s * pts[i][1], y + s * pts[i][2], x + s * pts[i + 1][1], y + s * pts[i + 1][2], th, nil, 0x22)
    end
end

function Art.iconBuilding(bb, x, y, s)
    B.brandebourg(bb, x, y + s * 0.1, s, s * 0.85, 0x22)
end

---------------------------------------------------------------------------
-- A different trophy for each city
---------------------------------------------------------------------------

local TROPHY = {}

-- st: { fill = rgb or nil, fg = fill grey, line = outline grey, base = base grey }
local function poly(bb, pts, st)
    Draw.polygon(bb, pts, st.fill, st.fg)
    local th = math.max(2, st.th)
    for i = 1, #pts do
        local a, b = pts[i], pts[i % #pts + 1]
        Draw.line(bb, a[1], a[2], b[1], b[2], th, nil, st.line)
    end
end

local function disc(bb, cx, cy, r, st)
    D(bb, cx, cy, r, st.line)
    D(bb, cx, cy, r - math.max(2, st.th), st.fg)
    if st.fill then Draw.disc(bb, math.floor(cx), math.floor(cy), math.max(1, math.floor(r - math.max(2, st.th))), st.fill, st.fg) end
end

local function box(bb, x, y, w, h, st)
    Draw.rect(bb, math.floor(x), math.floor(y), math.ceil(w), math.ceil(h), nil, st.line)
    local t = math.max(2, st.th)
    Draw.rect(bb, math.floor(x + t), math.floor(y + t), math.ceil(w - 2 * t), math.ceil(h - 2 * t), st.fill, st.fg)
end

local function base(bb, cx, y, w, h, st)
    -- dark two-tier base
    Draw.rect(bb, math.floor(cx - w * 0.5), math.floor(y + h * 0.45), math.ceil(w), math.ceil(h * 0.55), nil, st.base)
    Draw.rect(bb, math.floor(cx - w * 0.36), math.floor(y), math.ceil(w * 0.72), math.ceil(h * 0.5), nil, st.base)
    Draw.rect(bb, math.floor(cx - w * 0.36 + st.th), math.floor(y + h * 0.12), math.ceil(w * 0.72 - 2 * st.th), math.max(1, math.floor(h * 0.08)), st.fill, st.fg)
end

local function ellipse(bb, cx, cy, rx, ry, ang, th, g)
    local n = 48
    local ca, sa = math.cos(ang), math.sin(ang)
    local px, py
    for i = 0, n do
        local t = i / n * 2 * math.pi
        local ex, ey = rx * math.cos(t), ry * math.sin(t)
        local x = cx + ex * ca - ey * sa
        local y = cy + ex * sa + ey * ca
        if px then Draw.line(bb, px, py, x, y, th, nil, g) end
        px, py = x, y
    end
end

-- Brussels: the atom
TROPHY.bruxelles = function(bb, x, y, w, h, st)
    local cx = x + w / 2
    base(bb, cx, y + h * 0.82, w * 0.62, h * 0.18, st)
    box(bb, cx - w * 0.05, y + h * 0.55, w * 0.1, h * 0.28, st)
    local cy, r = y + h * 0.32, math.min(w, h) * 0.28
    local th = math.max(2, st.th)
    ellipse(bb, cx, cy, r, r * 0.38, 0.5, th, st.line)
    ellipse(bb, cx, cy, r, r * 0.38, -0.5, th, st.line)
    ellipse(bb, cx, cy, r, r * 0.38, math.pi / 2, th, st.line)
    disc(bb, cx, cy, r * 0.32, st)
end

-- Paris: the slender flute
TROPHY.paris = function(bb, x, y, w, h, st)
    local cx = x + w / 2
    base(bb, cx, y + h * 0.84, w * 0.5, h * 0.16, st)
    poly(bb, { { cx - w * 0.06, y + h * 0.84 }, { cx - w * 0.02, y + h * 0.48 }, { cx + w * 0.02, y + h * 0.48 }, { cx + w * 0.06, y + h * 0.84 } }, st)
    poly(bb, { { cx - w * 0.2, y + h * 0.04 }, { cx + w * 0.2, y + h * 0.04 }, { cx + w * 0.03, y + h * 0.5 }, { cx - w * 0.03, y + h * 0.5 } }, st)
    -- small star
    D(bb, cx, y + h * 0.2, math.max(2, w * 0.03), st.line)
end

-- London: the big lidded cup with large handles
TROPHY.londres = function(bb, x, y, w, h, st)
    local cx = x + w / 2
    local cw = math.min(w * 0.5, h * 0.42)
    base(bb, cx, y + h * 0.84, cw * 1.3, h * 0.16, st)
    box(bb, cx - cw * 0.08, y + h * 0.6, cw * 0.16, h * 0.25, st)
    Draw.ring(bb, math.floor(cx - cw * 0.6), math.floor(y + h * 0.35), math.floor(cw * 0.3), math.max(2, st.th + 1), nil, st.line)
    Draw.ring(bb, math.floor(cx + cw * 0.6), math.floor(y + h * 0.35), math.floor(cw * 0.3), math.max(2, st.th + 1), nil, st.line)
    poly(bb, { { cx - cw / 2, y + h * 0.2 }, { cx + cw / 2, y + h * 0.2 }, { cx + cw * 0.38, y + h * 0.5 }, { cx + cw * 0.12, y + h * 0.62 },
        { cx - cw * 0.12, y + h * 0.62 }, { cx - cw * 0.38, y + h * 0.5 } }, st)
    -- lid
    poly(bb, { { cx - cw * 0.45, y + h * 0.2 }, { cx - cw * 0.3, y + h * 0.1 }, { cx + cw * 0.3, y + h * 0.1 }, { cx + cw * 0.45, y + h * 0.2 } }, st)
    disc(bb, cx, y + h * 0.07, cw * 0.09, st)
end

-- Madrid: the salver
TROPHY.madrid = function(bb, x, y, w, h, st)
    local cx = x + w / 2
    local r = math.min(w * 0.4, h * 0.34)
    base(bb, cx, y + h * 0.84, w * 0.46, h * 0.16, st)
    box(bb, cx - w * 0.04, y + h * 0.66, w * 0.08, h * 0.2, st)
    local cy = y + h * 0.36
    disc(bb, cx, cy, r, st)
    Draw.ring(bb, math.floor(cx), math.floor(cy), math.floor(r * 0.72), math.max(2, st.th), nil, st.line)
    -- motif: a stylised chess rook
    local s2 = r * 0.5
    Draw.rect(bb, math.floor(cx - s2 * 0.35), math.floor(cy - s2 * 0.3), math.ceil(s2 * 0.7), math.ceil(s2 * 0.8), nil, st.line)
    for i = 0, 2 do Draw.rect(bb, math.floor(cx - s2 * 0.45 + i * s2 * 0.35), math.floor(cy - s2 * 0.5), math.ceil(s2 * 0.2), math.ceil(s2 * 0.25), nil, st.line) end
    Draw.rect(bb, math.floor(cx - s2 * 0.5), math.floor(cy + s2 * 0.45), math.ceil(s2), math.ceil(s2 * 0.18), nil, st.line)
end

-- Rome: the laurel wreath
TROPHY.rome = function(bb, x, y, w, h, st)
    local cx = x + w / 2
    base(bb, cx, y + h * 0.84, w * 0.62, h * 0.16, st)
    local cy, r = y + h * 0.42, math.min(w, h) * 0.3
    for side = -1, 1, 2 do
        for i = 0, 6 do
            local a = math.pi / 2 + side * (0.35 + i * 0.36)
            local lx, ly = cx + r * math.cos(a), cy + r * math.sin(a)
            local ang = a + side * math.pi / 2
            local lr = r * 0.26
            local p1 = { lx + lr * math.cos(ang), ly + lr * math.sin(ang) }
            local p2 = { lx + lr * 0.75 * math.cos(ang + 1.6), ly + lr * 0.75 * math.sin(ang + 1.6) }
            local p3 = { lx - lr * math.cos(ang), ly - lr * math.sin(ang) }
            local p4 = { lx + lr * 0.25 * math.cos(ang - 1.6), ly + lr * 0.25 * math.sin(ang - 1.6) }
            poly(bb, { p1, p2, p3, p4 }, st)
        end
    end
    -- ribbon
    poly(bb, { { cx - r * 0.25, cy + r * 1.0 }, { cx + r * 0.25, cy + r * 1.0 }, { cx + r * 0.4, cy + r * 1.35 }, { cx, cy + r * 1.15 }, { cx - r * 0.4, cy + r * 1.35 } }, st)
end

-- Berlin: the giant pawn
TROPHY.berlin = function(bb, x, y, w, h, st)
    local cx = x + w / 2
    base(bb, cx, y + h * 0.84, w * 0.62, h * 0.16, st)
    local s2 = math.min(w, h)
    poly(bb, { { cx - s2 * 0.25, y + h * 0.84 }, { cx - s2 * 0.08, y + h * 0.42 }, { cx + s2 * 0.08, y + h * 0.42 }, { cx + s2 * 0.25, y + h * 0.84 } }, st)
    box(bb, cx - s2 * 0.15, y + h * 0.36, s2 * 0.3, h * 0.07, st)
    disc(bb, cx, y + h * 0.22, s2 * 0.14, st)
end

-- Budapest: the crowned cup
TROPHY.budapest = function(bb, x, y, w, h, st)
    local cx = x + w / 2
    local cw = math.min(w * 0.56, h * 0.48)
    base(bb, cx, y + h * 0.84, cw * 1.1, h * 0.16, st)
    box(bb, cx - cw * 0.07, y + h * 0.62, cw * 0.14, h * 0.23, st)
    poly(bb, { { cx - cw / 2, y + h * 0.3 }, { cx + cw / 2, y + h * 0.3 }, { cx + cw * 0.15, y + h * 0.64 }, { cx - cw * 0.15, y + h * 0.64 } }, st)
    -- crown sitting on the cup
    poly(bb, { { cx - cw * 0.4, y + h * 0.3 }, { cx - cw * 0.44, y + h * 0.1 }, { cx - cw * 0.2, y + h * 0.2 }, { cx, y + h * 0.04 },
        { cx + cw * 0.2, y + h * 0.2 }, { cx + cw * 0.44, y + h * 0.1 }, { cx + cw * 0.4, y + h * 0.3 } }, st)
end

-- Reykjavik: the ice crystal
TROPHY.reykjavik = function(bb, x, y, w, h, st)
    local cx = x + w / 2
    local s2 = math.min(w * 0.36, h * 0.3)
    base(bb, cx, y + h * 0.84, w * 0.56, h * 0.16, st)
    local top, bot = y + h * 0.04, y + h * 0.84
    poly(bb, { { cx, top }, { cx + s2 * 0.6, top + (bot - top) * 0.25 }, { cx + s2 * 0.6, bot - (bot - top) * 0.12 }, { cx, bot },
        { cx - s2 * 0.6, bot - (bot - top) * 0.12 }, { cx - s2 * 0.6, top + (bot - top) * 0.25 } }, st)
    local th = math.max(1, st.th - 1)
    Draw.line(bb, cx, top, cx, bot, th, nil, st.line)
    Draw.line(bb, cx - s2 * 0.6, top + (bot - top) * 0.25, cx, top + (bot - top) * 0.4, th, nil, st.line)
    Draw.line(bb, cx + s2 * 0.6, top + (bot - top) * 0.25, cx, top + (bot - top) * 0.4, th, nil, st.line)
end

-- Buenos Aires: the star on its column
TROPHY.buenosaires = function(bb, x, y, w, h, st)
    local cx = x + w / 2
    base(bb, cx, y + h * 0.84, w * 0.56, h * 0.16, st)
    box(bb, cx - w * 0.06, y + h * 0.5, w * 0.12, h * 0.35, st)
    local cy, r = y + h * 0.27, math.min(w, h) * 0.26
    local pts = {}
    for i = 0, 9 do
        local a = -math.pi / 2 + i * math.pi / 5
        local rr = (i % 2 == 0) and r or r * 0.45
        pts[#pts + 1] = { cx + rr * math.cos(a), cy + rr * math.sin(a) }
    end
    poly(bb, pts, st)
end

-- Tokyo: the medal and its ribbon
TROPHY.tokyo = function(bb, x, y, w, h, st)
    local cx = x + w / 2
    local r = math.min(w, h) * 0.25
    -- V-shaped ribbon
    poly(bb, { { cx - r * 0.9, y + h * 0.02 }, { cx - r * 0.3, y + h * 0.02 }, { cx + r * 0.15, y + h * 0.45 }, { cx - r * 0.35, y + h * 0.45 } }, { fill = st.fill and { 236, 160, 160 } or nil, fg = 0xE8, line = st.line, th = st.th })
    poly(bb, { { cx + r * 0.9, y + h * 0.02 }, { cx + r * 0.3, y + h * 0.02 }, { cx - r * 0.15, y + h * 0.45 }, { cx + r * 0.35, y + h * 0.45 } }, { fill = st.fill and { 250, 246, 240 } or nil, fg = 0xB0, line = st.line, th = st.th })
    local cy = y + h * 0.58
    disc(bb, cx, cy, r, st)
    Draw.ring(bb, math.floor(cx), math.floor(cy), math.floor(r * 0.7), math.max(2, st.th), nil, st.line)
    D(bb, cx, cy, r * 0.25, st.line)
end

function Art.cityTrophy(bb, cityId, x, y, w, h, rgb, empty)
    local f = TROPHY[cityId]
    local th = math.max(2, math.floor(math.min(w, h) * 0.03))
    local st
    if empty then
        st = { fill = nil, fg = 0xF2, line = 0xC8, base = 0xE0, th = th }
    else
        st = { fill = rgb, fg = 0xC8, line = 0x33, base = 0x33, th = th }
    end
    if f then f(bb, x, y, w, h, st) else Art.trophy(bb, x, y, w, h, rgb, empty) end
end

return Art
