--[[
  Petite boîte à outils d'interface : écrans dessinés « à la main »
  (zones touchables, texte, boutons discrets), adaptés à l'encre électronique.
]]

local Blitbuffer = require("ffi/blitbuffer")
local Device = require("device")
local Font = require("ui/font")
local Geom = require("ui/geometry")
local GestureRange = require("ui/gesturerange")
local InputContainer = require("ui/widget/container/inputcontainer")
local RenderText = require("ui/rendertext")
local UIManager = require("ui/uimanager")
local Draw = require("cc_draw")
local Screen = Device.screen

local UI = {}

UI.BLACK = Blitbuffer.COLOR_BLACK
UI.WHITE = Blitbuffer.COLOR_WHITE
UI.GRAY = Blitbuffer.Color8(0x88)
UI.LIGHT = Blitbuffer.Color8(0xBB)
UI.DIM = Blitbuffer.Color8(0x66)
UI.MID = Blitbuffer.Color8(0xA8)

-- Couleurs pastel
UI.GOLD = { 236, 208, 120 }
UI.GREEN = { 160, 212, 150 }
UI.RED = { 236, 150, 150 }
UI.BLUE = { 160, 196, 236 }
UI.SAND = { 240, 228, 200 }

function UI.s(px) return Screen:scaleBySize(px) end

local faces = {}
function UI.face(size, bold)
    local k = (bold and "b" or "r") .. size
    if not faces[k] then faces[k] = Font:getFace(bold and "tfont" or "cfont", size) end
    return faces[k]
end

function UI.pieceFace(px)
    return Draw.faceForPixels("freefont/FreeSerif.ttf", px)
end

function UI.textWidth(face, text, bold)
    if not text or text == "" then return 0 end
    return RenderText:sizeUtf8Text(0, nil, face, text, true, bold).x
end

-- Texte dont le haut est en y. Renvoie la largeur.
function UI.text(bb, face, text, x, y, color, bold)
    if not text or text == "" then return 0 end
    local baseline = y + math.floor(face.size * 0.95)
    return RenderText:renderUtf8Text(bb, math.floor(x), baseline, face, text, true, bold, color or UI.BLACK) or 0
end

function UI.lineHeight(face) return math.floor(face.size * 1.38) end

function UI.textCentered(bb, face, text, cx, y, color, bold)
    local w = UI.textWidth(face, text, bold)
    UI.text(bb, face, text, cx - w / 2, y, color, bold)
    return w
end

function UI.textRight(bb, face, text, rx, y, color, bold)
    local w = UI.textWidth(face, text, bold)
    UI.text(bb, face, text, rx - w, y, color, bold)
    return w
end

-- Coupe un texte en lignes de largeur maximale `maxw`
function UI.wrap(face, text, maxw, bold)
    local lines = {}
    local space = UI.textWidth(face, " ", bold)
    for para in (text .. "\n"):gmatch("(.-)\n") do
        if para == "" then
            lines[#lines + 1] = ""
        else
            local cur, curw = "", 0
            for word in para:gmatch("%S+") do
                local ww = UI.textWidth(face, word, bold)
                if cur == "" then
                    cur, curw = word, ww
                elseif curw + space + ww <= maxw then
                    cur = cur .. " " .. word
                    curw = curw + space + ww
                else
                    lines[#lines + 1] = cur
                    cur, curw = word, ww
                end
            end
            lines[#lines + 1] = cur
        end
    end
    return lines
end

-- Raccourcit un texte trop long avec « … »
function UI.ellipsize(face, text, maxw, bold)
    if UI.textWidth(face, text, bold) <= maxw then return text end
    local chars = {}
    for c in text:gmatch("[%z\1-\127\194-\244][\128-\191]*") do chars[#chars + 1] = c end
    while #chars > 0 do
        chars[#chars] = nil
        local t = table.concat(chars) .. "…"
        if UI.textWidth(face, t, bold) <= maxw then return t end
    end
    return "…"
end

-- Bouton « pilule » : contour arrondi fin, ou rempli (pastel) si fill
function UI.pill(bb, x, y, w, h, label, face, opts)
    opts = opts or {}
    local r = math.floor(h / 2)
    if opts.fill or opts.gray then
        Draw.roundedRect(bb, x, y, w, h, r, opts.fill, opts.gray or 0xD8)
    end
    if opts.dark then
        Draw.roundedRect(bb, x, y, w, h, r, nil, 0x00)
    end
    if not opts.noborder and not opts.dark then
        bb:paintBorder(x, y, w, h, math.max(1, UI.s(1)), opts.disabled and UI.LIGHT or UI.BLACK, r)
    end
    local color = opts.dark and UI.WHITE or (opts.disabled and UI.LIGHT or UI.BLACK)
    UI.textCentered(bb, face, label, x + w / 2, y + (h - UI.lineHeight(face)) / 2 + UI.s(1), color, opts.bold)
end

---------------------------------------------------------------------------
-- Écran de base
---------------------------------------------------------------------------

local Canvas = InputContainer:extend{
    covers_fullscreen = true,
    name = "chesscoach_canvas",
}
UI.Canvas = Canvas

function Canvas:init()
    self.W = Screen:getWidth()
    self.H = Screen:getHeight()
    self.dimen = Geom:new{ x = 0, y = 0, w = self.W, h = self.H }
    self.regions = {}
    local range = function() return self.dimen end
    self.ges_events = {
        CanvasTap = { GestureRange:new{ ges = "tap", range = range } },
        CanvasHold = { GestureRange:new{ ges = "hold", range = range } },
        CanvasSwipe = { GestureRange:new{ ges = "swipe", range = range } },
    }
    if Device:hasKeys() then
        self.key_events = self.key_events or {}
        self.key_events.CanvasPrev = { { Device.input.group.PgBack } }
        self.key_events.CanvasNext = { { Device.input.group.PgFwd } }
    end
    if self.setup then self:setup() end
end

function Canvas:paintTo(bb, x, y)
    self.regions = {}
    bb:paintRect(x, y, self.W, self.H, UI.WHITE)
    self:draw(bb, x, y)
end

function Canvas:draw() end

-- Zone touchable (les dernières ajoutées sont prioritaires)
function Canvas:region(x, y, w, h, cb, hold)
    self.regions[#self.regions + 1] = { x = x, y = y, w = w, h = h, cb = cb, hold = hold }
end

local function hit(regions, pos, field)
    for i = #regions, 1, -1 do
        local r = regions[i]
        if r[field] and pos.x >= r.x and pos.x < r.x + r.w and pos.y >= r.y and pos.y < r.y + r.h then
            return r
        end
    end
end

function Canvas:onCanvasTap(_, ges)
    local r = hit(self.regions, ges.pos, "cb")
    if r then r.cb(ges) end
    return true
end

function Canvas:onCanvasHold(_, ges)
    local r = hit(self.regions, ges.pos, "hold")
    if r then r.hold(ges)
    else
        r = hit(self.regions, ges.pos, "cb")
        if r then r.cb(ges) end
    end
    return true
end

function Canvas:onCanvasSwipe(_, ges)
    if self.onSwipe then self:onSwipe(ges.direction, ges) end
    return true
end

function Canvas:onCanvasPrev()
    if self.onPrevKey then self:onPrevKey() end
    return true
end

function Canvas:onCanvasNext()
    if self.onNextKey then self:onNextKey() end
    return true
end

function Canvas:refresh(mode, rect)
    if self.closed then return end
    UIManager:setDirty(self, mode or "ui", rect)
end

function Canvas:show(mode)
    UIManager:show(self, mode or "flashui")
end

-- refresh : type de rafraîchissement de l'écran du dessous ("flashui" par défaut,
-- "none" pour ne rien rafraîchir quand on ferme plusieurs écrans d'affilée)
function Canvas:close(refresh)
    if self.closed then return end
    self.closed = true
    if self.onClose then self:onClose() end
    if refresh == "none" then
        UIManager:close(self)
    else
        UIManager:close(self, refresh or "flashui")
    end
end

-- En-tête commun : titre à gauche, bouton retour « ‹ » à gauche
function Canvas:header(bb, title, backLabel, onBack)
    local m = UI.s(10)
    local f = UI.face(15)
    local h = UI.s(36)
    local x = m
    if onBack then
        local lbl = "‹ " .. (backLabel or "Retour")
        local w = UI.textWidth(f, lbl) + UI.s(12)
        UI.text(bb, f, lbl, x, (h - UI.lineHeight(f)) / 2 + UI.s(4))
        self:region(0, 0, w + m, h + UI.s(6), onBack)
        x = x + w + UI.s(12)
    end
    if title then
        UI.textCentered(bb, UI.face(16, true), title, self.W / 2, (h - UI.lineHeight(UI.face(16, true))) / 2 + UI.s(4), UI.BLACK, false)
    end
    bb:paintRect(m, h, self.W - 2 * m, 1, UI.LIGHT)
    return h + UI.s(4)
end

return UI
