--[[
  L'échiquier : dessin des cases, pièces, flèches et pastilles du coach,
  et détection des touches sur les cases.
]]

local Blitbuffer = require("ffi/blitbuffer")
local Geom = require("ui/geometry")
local GestureRange = require("ui/gesturerange")
local InputContainer = require("ui/widget/container/inputcontainer")
local Chess = require("cc_chess")
local Coach = require("cc_coach")
local Draw = require("cc_draw")

local LIGHT = 0xFF
local DARK = 0xC2
local LIGHT_LAST = 0xE2
local DARK_LAST = 0xA4

-- Glyphes Unicode : contours (blancs) et pleins (noirs)
local OUTLINE = { k = 0x2654, q = 0x2655, r = 0x2656, b = 0x2657, n = 0x2658, p = 0x2659 }
local FILLED  = { k = 0x265A, q = 0x265B, r = 0x265C, b = 0x265D, n = 0x265E, p = 0x265F }

local Board = InputContainer:extend{
    size = 800,
    flipped = false,
    pos = nil,
    selected = nil,       -- case sélectionnée
    targets = nil,        -- { [case] = true } coups possibles
    last_move = nil,      -- { from, to }
    arrows = nil,         -- { { from, to, rgb, gray } }
    badges = nil,         -- { { sq, cat } }
    marks = nil,          -- { { sq, rgb, gray } } cercles de couleur
    on_tap = nil,         -- function(case)
}

function Board:init()
    self.sq = math.floor(self.size / 8)
    self.size = self.sq * 8
    self.dimen = Geom:new{ x = 0, y = 0, w = self.size, h = self.size }
    self.piece_face = Draw.faceForPixels("freefont/FreeSerif.ttf", math.floor(self.sq * 0.88))
    self.coord_face = Draw.faceForPixels("cfont", math.max(10, math.floor(self.sq * 0.16)))
    self.badge_face = Draw.faceForPixels("cfont", math.max(10, math.floor(self.sq * 0.22)))
    self.ges_events = {
        TapBoard = { GestureRange:new{ ges = "tap", range = function() return self.dimen end } },
    }
end

function Board:getSize()
    return Geom:new{ w = self.size, h = self.size }
end

-- Coin haut-gauche d'une case à l'écran (relatif à l'échiquier)
function Board:squareOrigin(sq)
    local f, r = Chess.fileOf(sq), Chess.rankOf(sq)
    local col, row
    if self.flipped then
        col, row = 7 - f, r
    else
        col, row = f, 7 - r
    end
    return col * self.sq, row * self.sq
end

function Board:squareCenter(sq)
    local x, y = self:squareOrigin(sq)
    return x + self.sq / 2, y + self.sq / 2
end

-- Case sous un point de l'écran (nil si hors de l'échiquier)
function Board:squareAt(px, py)
    local x = px - self.dimen.x
    local y = py - self.dimen.y
    local col = math.floor(x / self.sq)
    local row = math.floor(y / self.sq)
    if col < 0 or col > 7 or row < 0 or row > 7 then return nil end
    if self.flipped then return row * 8 + (7 - col) end
    return (7 - row) * 8 + col
end

function Board:onTapBoard(_, ges)
    local x = ges.pos.x - self.dimen.x
    local y = ges.pos.y - self.dimen.y
    local col = math.floor(x / self.sq)
    local row = math.floor(y / self.sq)
    if col < 0 or col > 7 or row < 0 or row > 7 then return true end
    local f, r
    if self.flipped then
        f, r = 7 - col, row
    else
        f, r = col, 7 - row
    end
    if self.on_tap then self.on_tap(r * 8 + f) end
    return true
end

function Board:paintTo(bb, x, y)
    self.dimen.x, self.dimen.y = x, y
    local sq = self.sq
    local pos = self.pos

    -- cases
    for s = 0, 63 do
        local ox, oy = self:squareOrigin(s)
        local light = (Chess.fileOf(s) + Chess.rankOf(s)) % 2 == 1
        local shade = light and LIGHT or DARK
        if self.last_move and (s == self.last_move.from or s == self.last_move.to) then
            shade = light and LIGHT_LAST or DARK_LAST
        end
        if self.premove and (s == self.premove.from or s == self.premove.to) then
            Draw.rect(bb, x + ox, y + oy, sq, sq, light and { 190, 214, 240 } or { 150, 184, 222 }, light and 0xB8 or 0x90)
        else
            bb:paintRect(x + ox, y + oy, sq, sq, Blitbuffer.Color8(shade))
        end
    end

    -- coordonnées discrètes
    for i = 0, 7 do
        -- lettres sur la rangée du bas
        local fileSq = self.flipped and (7 - i) or i
        local bottomSq = self.flipped and (56 + fileSq) or fileSq
        local ox, oy = self:squareOrigin(bottomSq)
        local light = (Chess.fileOf(bottomSq) + Chess.rankOf(bottomSq)) % 2 == 1
        Draw.textCentered(bb, self.coord_face, ("abcdefgh"):sub(fileSq + 1, fileSq + 1),
            x + ox + sq - sq * 0.1, y + oy + sq - sq * 0.12,
            Blitbuffer.Color8(light and 0x90 or 0xFF))
        -- chiffres sur la colonne de gauche
        local rank = self.flipped and i or (7 - i)
        local leftSq = rank * 8 + (self.flipped and 7 or 0)
        ox, oy = self:squareOrigin(leftSq)
        light = (Chess.fileOf(leftSq) + Chess.rankOf(leftSq)) % 2 == 1
        Draw.textCentered(bb, self.coord_face, tostring(rank + 1),
            x + ox + sq * 0.1, y + oy + sq * 0.13,
            Blitbuffer.Color8(light and 0x90 or 0xFF))
    end

    -- marques de couleur (indice)
    for _, mk in ipairs(self.marks or {}) do
        local cx, cy = self:squareCenter(mk.sq)
        Draw.disc(bb, x + math.floor(cx), y + math.floor(cy), math.floor(sq * 0.46), mk.rgb, mk.gray)
    end

    -- case sélectionnée
    if self.selected then
        local ox, oy = self:squareOrigin(self.selected)
        bb:paintBorder(x + ox, y + oy, sq, sq, math.max(3, math.floor(sq * 0.05)), Blitbuffer.COLOR_BLACK)
    end

    -- pièces
    if pos then
        for s = 0, 63 do
            local p = pos.board[s]
            if p then
                local cx, cy = self:squareCenter(s)
                local l = p:lower()
                local px, py = x + cx, y + cy + sq * 0.02
                if p == p:upper() then
                    -- pièce blanche : silhouette blanche + contour noir
                    Draw.glyphCentered(bb, self.piece_face, FILLED[l], px, py, Blitbuffer.COLOR_WHITE, OUTLINE[l])
                    Draw.glyphCentered(bb, self.piece_face, OUTLINE[l], px, py, Blitbuffer.COLOR_BLACK)
                else
                    Draw.glyphCentered(bb, self.piece_face, FILLED[l], px, py, Blitbuffer.COLOR_BLACK)
                end
            end
        end
    end

    -- coups possibles
    for s in pairs(self.targets or {}) do
        local cx, cy = self:squareCenter(s)
        if pos and pos.board[s] then
            bb:paintCircle(x + math.floor(cx), y + math.floor(cy), math.floor(sq * 0.46),
                Blitbuffer.Color8(0x40), math.max(3, math.floor(sq * 0.06)))
        else
            bb:paintCircle(x + math.floor(cx), y + math.floor(cy), math.floor(sq * 0.13),
                Blitbuffer.Color8(0x40))
        end
    end

    -- flèches
    for _, a in ipairs(self.arrows or {}) do
        local x0, y0 = self:squareCenter(a.from)
        local x1, y1 = self:squareCenter(a.to)
        Draw.arrow(bb, x + x0, y + y0, x + x1, y + y1, sq, a.rgb, a.gray)
    end

    -- pastilles du coach (en haut à droite de la case)
    for _, b in ipairs(self.badges or {}) do
        local cat = Coach.CATEGORIES[b.cat]
        if cat then
            local ox, oy = self:squareOrigin(b.sq)
            local bs = math.floor(sq * 0.40)
            local bx = x + ox + sq - bs - 2
            local by = y + oy + 2
            if b.big then
                -- dépasse légèrement de la case, comme sur chess.com
                bx = bx + math.floor(bs * 0.25)
                by = by - math.floor(bs * 0.25)
                if by < y then by = y end
                if bx + bs > x + self.size then bx = x + self.size - bs end
            end
            Draw.disc(bb, bx + math.floor(bs / 2), by + math.floor(bs / 2), math.floor(bs / 2), nil, 0x20)
            Draw.disc(bb, bx + math.floor(bs / 2), by + math.floor(bs / 2), math.floor(bs / 2) - 2, cat.color, cat.gray)
            Draw.textCentered(bb, self.badge_face, cat.symbol, bx + bs / 2, by + bs / 2,
                Blitbuffer.COLOR_BLACK, true)
        end
    end

    -- cadre
    bb:paintBorder(x, y, self.size, self.size, 2, Blitbuffer.COLOR_BLACK)
end

return Board
