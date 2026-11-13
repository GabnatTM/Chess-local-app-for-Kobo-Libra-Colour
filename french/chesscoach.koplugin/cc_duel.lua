--[[
  Duel local : deux joueurs face à face sur la même liseuse.
  - Les Blancs sont en bas, les Noirs en haut ; les pièces noires et tout le
    panneau des Noirs (pendule, boutons) sont tournés vers le joueur d'en face.
  - Pendules : 3 + 2, 5 + 5, 10 + 5, 15 + 10.
  - La partie en cours est sauvegardée (data.duel) et peut être reprise.
  La logique (Duel) est séparée de l'écran pour être testée sur ordinateur.
]]

local Chess = require("cc_chess")

local DuelMod = {}

DuelMod.CADENCES = {
    { id = "3+2",   name = "3 + 2",   base = 180, inc = 2 },
    { id = "5+5",   name = "5 + 5",   base = 300, inc = 5 },
    { id = "10+5",  name = "10 + 5",  base = 600, inc = 5 },
    { id = "15+10", name = "15 + 10", base = 900, inc = 10 },
}

function DuelMod.cadence(id)
    for _, c in ipairs(DuelMod.CADENCES) do if c.id == id then return c end end
    return DuelMod.CADENCES[3]
end

---------------------------------------------------------------------------
-- Logique d'une partie
---------------------------------------------------------------------------

local Duel = {}
Duel.__index = Duel
DuelMod.Duel = Duel

-- Nouvelle partie (table sauvegardable)
function DuelMod.newGame(cadence_id)
    local c = DuelMod.cadence(cadence_id)
    return { cadence = c.id, base = c.base, inc = c.inc, moves = {}, clock = { w = c.base, b = c.base },
        result = nil, reason = nil, started = os.time() }
end

-- g : table sauvegardée ; now : horloge en secondes (monotone)
function Duel.new(g, now)
    local self = setmetatable({ g = g, now = now or os.time }, Duel)
    self:rebuild()
    self.running_since = nil -- la pendule ne tourne que quand l'écran est ouvert
    return self
end

function Duel:rebuild()
    local g = self.g
    self.positions = { Chess.new() }
    self.keys = { [self.positions[1]:key()] = 1 }
    self.last = nil
    for i, u in ipairs(g.moves) do
        local pos = self.positions[i]
        local m = pos:findUci(u)
        if not m then
            for k = #g.moves, i, -1 do g.moves[k] = nil end
            break
        end
        local nxt = pos:makeMove(m)
        self.positions[i + 1] = nxt
        self.keys[nxt:key()] = (self.keys[nxt:key()] or 0) + 1
        self.last = { from = m.from, to = m.to }
    end
end

function Duel:pos() return self.positions[#self.positions] end
function Duel:turn() return self:pos().turn end
function Duel:ended() return self.g.result ~= nil end

-- Temps restant (en tenant compte du temps qui s'écoule)
function Duel:clock(color)
    local t = self.g.clock[color]
    if self.running_since and not self:ended() and self:turn() == color then
        t = t - (self.now() - self.running_since)
    end
    return math.max(0, t)
end

-- La pendule tourne-t-elle ? (pas avant le premier coup des Blancs)
function Duel:clockStarted() return #self.g.moves >= 1 end

function Duel:_commitTime()
    if self.running_since and not self:ended() then
        local side = self:turn()
        local t = self.now()
        self.g.clock[side] = self.g.clock[side] - (t - self.running_since)
        self.running_since = t
    end
end

function Duel:start()
    if self:ended() or not self:clockStarted() then self.running_since = nil return end
    self.running_since = self.running_since or self.now()
end

function Duel:pause()
    self:_commitTime()
    self.running_since = nil
end

function Duel:paused() return self.running_since == nil end

function Duel:finish(result, reason)
    self:_commitTime()
    self.running_since = nil
    self.g.result = result
    self.g.reason = reason
end

-- Vérifie la chute du drapeau ; renvoie true si la partie vient de finir
function Duel:checkFlag()
    if self:ended() or not self.running_since then return false end
    local side = self:turn()
    if self:clock(side) > 0 then return false end
    self:_commitTime()
    self.g.clock[side] = 0
    local other = Chess.other(side)
    -- l'adversaire ne peut pas mater : nulle
    local pos = self:pos()
    local hasMaterial = false
    for sq = 0, 63 do
        local p = pos.board[sq]
        if p and Chess.colorOf(p) == other and p:lower() ~= "k" then hasMaterial = true break end
    end
    if hasMaterial then
        self:finish(other == "w" and "1-0" or "0-1", "temps écoulé")
    else
        self:finish("1/2-1/2", "temps écoulé, matériel insuffisant")
    end
    return true
end

function Duel:play(m)
    if self:ended() then return false end
    if self:checkFlag() then return false end
    local pos = self:pos()
    local mover = pos.turn
    self:_commitTime()
    local nxt = pos:makeMove(m)
    local g = self.g
    g.moves[#g.moves + 1] = Chess.moveToUci(m)
    self.positions[#self.positions + 1] = nxt
    self.keys[nxt:key()] = (self.keys[nxt:key()] or 0) + 1
    self.last = { from = m.from, to = m.to }
    -- incrément (sauf pour le tout premier coup, pendule pas encore lancée)
    if #g.moves > 1 then g.clock[mover] = g.clock[mover] + g.inc end
    g.draw_offer = nil
    local st = nxt:status(self.keys[nxt:key()])
    if st then
        self:finish(st.result, st.reason)
    else
        self.running_since = self.now()
    end
    return true
end

function Duel:undo()
    local g = self.g
    if #g.moves == 0 then return false end
    self:_commitTime()
    g.moves[#g.moves] = nil
    g.result, g.reason, g.draw_offer = nil, nil, nil
    self:rebuild()
    if not self:clockStarted() then
        self.running_since = nil
        g.clock = { w = g.base, b = g.base }
    end
    return true
end

function Duel:resign(color)
    self:finish(color == "w" and "0-1" or "1-0", "abandon")
end

function Duel:agreeDraw() self:finish("1/2-1/2", "nulle par accord") end

-- Différence de matériel (pour l'affichage « +2 »)
function Duel:materialDiff(color)
    local pos = self:pos()
    return pos:material(color) - pos:material(Chess.other(color))
end

---------------------------------------------------------------------------
-- Écrans
---------------------------------------------------------------------------

function DuelMod.screens()
    local Blitbuffer = require("ffi/blitbuffer")
    local UIManager = require("ui/uimanager")
    local ConfirmBox = require("ui/widget/confirmbox")
    local Geom = require("ui/geometry")
    local Board = require("cc_board")
    local Draw = require("cc_draw")
    local UI = require("cc_ui")
    local s = UI.s
    local Screens = {}

    -------------------------------------------------------------------
    -- Choix de la pendule
    -------------------------------------------------------------------
    local Setup = UI.Canvas:extend{ app = nil }
    Screens.Setup = Setup

    function Setup:setup()
        self.cadence = self.app.profile.duel_cadence or "10+5"
    end

    function Setup:draw(bb)
        local app = self.app
        local W = self.W
        local m = s(20)
        local y = self:header(bb, "Duel local", "Menu", function() self:close() end)
        y = y + s(16)
        local dg = app.data.duel
        if dg and not dg.result and #dg.moves > 0 then
            local bw = W - 2 * m
            bb:paintBorder(m, y, bw, s(70), s(1), UI.BLACK, s(12))
            UI.text(bb, UI.face(17, true), "Reprendre le duel en cours", m + s(16), y + s(10))
            UI.text(bb, UI.face(14), "Pendule " .. DuelMod.cadence(dg.cadence).name .. " · " .. #dg.moves .. " coups joués",
                m + s(16), y + s(38), UI.DIM)
            UI.textRight(bb, UI.face(22), "›", m + bw - s(14), y + s(18), UI.GRAY)
            self:region(m, y, bw, s(70), function() app:openDuelGame(dg) end)
            y = y + s(90)
        end
        UI.text(bb, UI.face(16, true), "Pendule", m, y)
        y = y + UI.lineHeight(UI.face(16, true)) + s(4)
        local x = m
        local f = UI.face(15)
        for _, c in ipairs(DuelMod.CADENCES) do
            local w = UI.textWidth(f, c.name) + s(36)
            if x + w > W - m then x = m; y = y + s(48) end
            local sel = c.id == self.cadence
            UI.pill(bb, x, y, w, s(38), c.name, f, sel and { dark = true } or {})
            self:region(x, y, w, s(38), function() self.cadence = c.id; self:refresh() end)
            x = x + w + s(10)
        end
        y = y + s(60)
        UI.text(bb, UI.face(16, true), "Échiquier", m, y)
        y = y + UI.lineHeight(UI.face(16, true)) + s(4)
        x = m
        local flip = app.profile.duel_flip ~= false
        for _, o in ipairs({ { true, "Pièces tournées vers celui qui joue" }, { false, "Fixe, pièces d'en face à l'envers" } }) do
            local w = UI.textWidth(f, o[2]) + s(36)
            if x + w > W - m then x = m; y = y + s(48) end
            UI.pill(bb, x, y, w, s(38), o[2], f, (o[1] == flip) and { dark = true } or {})
            self:region(x, y, w, s(38), function() app.profile.duel_flip = o[1]; self:refresh() end)
            x = x + w + s(10)
        end
        y = y + s(60)
        local txt = "Jouez à deux sur la même liseuse : posez-la à plat entre vous. Les Blancs sont en bas, "
            .. "les Noirs en haut. Chacun garde sa pendule de son côté ; les pièces se tournent vers celui qui doit jouer (ou restent fixes, pièces d'en face à l'envers). "
            .. "La pendule démarre au premier coup des Blancs. Cette partie ne compte pas pour votre Elo."
        for _, l in ipairs(UI.wrap(UI.face(14), txt, W - 2 * m)) do
            UI.text(bb, UI.face(14), l, m, y, UI.DIM)
            y = y + UI.lineHeight(UI.face(14))
        end
        y = y + s(24)
        local bw = s(240)
        UI.pill(bb, (W - bw) / 2, y, bw, s(46), "Commencer", UI.face(18, true), { dark = true })
        self:region((W - bw) / 2, y, bw, s(46), function()
            app.profile.duel_cadence = self.cadence
            local start = function() app:startDuel(self.cadence) end
            if dg and not dg.result and #dg.moves >= 2 then
                UIManager:show(ConfirmBox:new{
                    text = "Le duel en cours sera effacé. Commencer une nouvelle partie ?",
                    ok_text = "Nouvelle partie", cancel_text = "Annuler", ok_callback = start,
                })
            else
                start()
            end
        end)
    end

    -------------------------------------------------------------------
    -- La partie
    -------------------------------------------------------------------
    local Game = UI.Canvas:extend{ app = nil, game = nil }
    Screens.Game = Game

    local function fmtClock(t)
        t = math.max(0, t)
        if t < 10 then
            return (string.format("0:%04.1f", math.floor(t * 10) / 10):gsub("%.", ","))
        end
        local secs = math.ceil(t - 0.001)
        return string.format("%d:%02d", math.floor(secs / 60), secs % 60)
    end

    function Game:setup()
        self.duel = Duel.new(self.game, self.app._clock)
        self.mg = s(6)
        -- l'échiquier prend toute la largeur de l'écran
        local bs = math.min(self.W, self.H - 2 * s(52))
        bs = bs - bs % 8
        self.flip_mode = self.app.profile.duel_flip ~= false
        self.board = Board:new{ size = bs }
        self.bs = bs
        self.panel_h = math.floor((self.H - bs) / 2)
        self.panel = { w = "normal", b = "normal" } -- mode du panneau de chaque joueur
        self.selected, self.targets = nil, nil
        self.promo = nil
        self.duel:start()
        self:tick()
    end

    function Game:tick()
        if self.closed then return end
        local d = self.duel
        if d:checkFlag() then
            self:onEnded()
        end
        if not d:ended() and not d:paused() then
            local t = d:clock(d:turn())
            local nxt = t < 10 and 0.2 or (t < 60 and 0.5 or 1)
            local r = self.clock_rect and self.clock_rect[d:turn()]
            self:refresh("fast", r and Geom:new{ x = r.x, y = r.y, w = r.w, h = r.h } or nil)
            UIManager:scheduleIn(nxt, function() self:tick() end)
            self.ticking = true
        else
            self.ticking = false
        end
    end

    function Game:ensureTicking()
        if not self.ticking then self:tick() end
    end

    function Game:save() self.app:save() end

    function Game:onClose()
        self.duel:pause()
        self:save()
    end

    function Game:onEnded()
        self.panel = { w = "fin", b = "fin" }
        self.selected, self.targets, self.promo = nil, nil, nil
        self:save()
        self:refresh("ui")
    end

    -- Dessine la bande d'un joueur (le plateau est au-dessus de la bande, le joueur en dessous).
    -- Très peu d'éléments : la pendule en petit, Pause, et Fermer chez les Blancs.
    -- reg(x, y, w, h, cb) ajoute une zone touchable ; renvoie le rectangle de la pendule.
    function Game:drawPanel(pb, w, h, color, reg)
        local d = self.duel
        local g = d.g
        local mine = not d:ended() and d:turn() == color
        local m = s(12)
        local mode = self.panel[color]
        local f = UI.face(14)
        local bh = s(36)
        local cy = math.floor((h - bh) / 2)

        -- la pendule (petite), à gauche
        local t = d:clock(color)
        local active = mine and d:clockStarted() and not d:paused()
        local low = t < 30
        local cf = UI.face(17, true)
        local cw = s(96)
        if active and low then
            Draw.roundedRect(pb, m, cy, cw, bh, math.floor(bh / 2), UI.RED, 0x90)
        elseif active then
            Draw.roundedRect(pb, m, cy, cw, bh, math.floor(bh / 2), nil, 0x00)
        else
            pb:paintBorder(m, cy, cw, bh, s(1), UI.BLACK, math.floor(bh / 2))
        end
        UI.textCentered(pb, cf, fmtClock(t), m + cw / 2, cy + (bh - UI.lineHeight(cf)) / 2 + s(2),
            (active and not low) and UI.WHITE or UI.BLACK)
        local clockRect = { x = m, y = cy, w = cw, h = bh }
        local x = m + cw + s(12)

        -- petit texte d'état juste à côté de la pendule
        local note
        if d:ended() then
            local res = g.result
            if res == "1/2-1/2" then note = "Partie nulle"
            elseif (res == "1-0") == (color == "w") then note = "Victoire !"
            else note = "Défaite" end
            note = note .. (g.reason and (" · " .. g.reason) or "")
        elseif mode == "pause" then
            note = "Pause"
        elseif mode == "promo" then
            note = "Promotion :"
        elseif mode == "abandon" then
            note = "Abandonner ?"
        elseif mine and d:pos():inCheck() then
            note = "Échec !"
        end

        -- boutons, à droite
        local items
        if mode == "promo" and self.promo then
            items = {}
            for _, nm in ipairs({ { "q", "Dame" }, { "r", "Tour" }, { "b", "Fou" }, { "n", "Cavalier" } }) do
                local mv = self.promo.cands[nm[1]]
                if mv then items[#items + 1] = { nm[2], function() self:doMove(mv) end, true } end
            end
            items[#items + 1] = { "✕", function() self.promo = nil; self.panel[color] = "normal"; self:refresh("ui") end }
        elseif d:ended() then
            items = { { "Revanche", function() self:rematch() end, true } }
            if color == self:bottomColor() then items[#items + 1] = { "Fermer", function() self:close() end } end
        elseif mode == "abandon" then
            items = {
                { "Oui", function() d:resign(color); self:onEnded() end, true },
                { "Non", function() self.panel[color] = "pause"; self:refresh("ui") end },
            }
        elseif mode == "pause" then
            items = {
                { "Reprendre", function()
                    self.panel = { w = "normal", b = "normal" }
                    d:start(); self:save(); self:refresh("ui"); self:ensureTicking()
                end, true },
                { "Annuler le coup", function()
                    d:undo(); self.selected, self.targets = nil, nil
                    self:save(); self:refresh("ui")
                end, false, #g.moves == 0 },
                { "Nulle", function() d:agreeDraw(); self:onEnded() end, false, #g.moves < 2 },
                { "Abandon", function() self.panel[color] = "abandon"; self:refresh("ui") end, false, #g.moves < 2 },
            }
        else
            items = { { "Pause", function()
                d:pause()
                self.panel = { w = "pause", b = "pause" }
                self.selected, self.targets = nil, nil
                self:save(); self:refresh("ui")
            end } }
            if color == self:bottomColor() then items[#items + 1] = { "Fermer", function() self:close() end } end
        end
        local widths, total = {}, 0
        for i, it in ipairs(items) do
            widths[i] = UI.textWidth(f, it[1]) + s(24)
            total = total + widths[i] + s(8)
        end
        local bx = w - m - total + s(8)
        if note then
            local nf = UI.face(14, d:ended())
            UI.text(pb, nf, UI.ellipsize(nf, note, math.max(s(40), bx - x - s(8))), x, cy + (bh - UI.lineHeight(nf)) / 2 + s(2))
        end
        for i, it in ipairs(items) do
            local dis = it[4]
            UI.pill(pb, bx, cy, widths[i], bh, it[1], f, it[3] and { dark = true } or (dis and { disabled = true } or {}))
            if not dis then reg(bx, cy - s(6), widths[i], bh + s(12), it[2]) end
            bx = bx + widths[i] + s(8)
        end
        return clockRect
    end

    -- Celui qui « regarde » l'écran : en mode tournant, le joueur au trait
    -- L'écran ne tourne plus : seules les pièces se retournent vers le joueur au trait
    function Game:viewer() return "w" end

    function Game:bottomColor() return "w" end

    -- Sens des pièces : vers le joueur au trait (mode « pièces qui se tournent »)
    function Game:piecesFacing()
        local d = self.duel
        if d:ended() then return self.last_facing or "w" end
        self.last_facing = d:turn()
        return self.last_facing
    end

    -- Dessine la disposition vue par `v` (son camp en bas) dans `bb` ;
    -- map(x, y, w, h) convertit un rectangle vers l'écran réel
    function Game:drawLayout(bb, v, map, reg)
        local W, ph = self.W, self.panel_h
        local top = v == "w" and "b" or "w"
        self.clock_rect = {}
        -- bande du bas (le joueur v, à l'endroit)
        local wy = ph + self.bs
        local cr = self:drawPanel(bb:viewport(0, wy, W, self.H - wy), W, self.H - wy, v,
            function(x, y, w, h, cb) reg(x, wy + y, w, h, cb) end)
        self.clock_rect[v] = map(cr.x, wy + cr.y, cr.w, cr.h)
        -- bande du haut : l'autre joueur. Échiquier fixe : tournée vers lui ; échiquier
        -- tournant : à l'endroit pour le joueur au trait
        do
            local tmp = Blitbuffer.new(W, ph, bb:getType())
            tmp:fill(UI.WHITE)
            local regs = {}
            cr = self:drawPanel(tmp, W, ph, top, function(x, y, w, h, cb) regs[#regs + 1] = { x, y, w, h, cb } end)
            local rot = tmp:rotatedCopy(180)
            bb:blitFrom(rot, 0, 0, 0, 0, W, ph)
            rot:free(); tmp:free()
            for _, r in ipairs(regs) do reg(W - r[1] - r[3], ph - r[2] - r[4], r[3], r[4], r[5]) end
            self.clock_rect[top] = map(W - cr.x - cr.w, ph - cr.y - cr.h, cr.w, cr.h)
        end
        -- l'échiquier
        local d = self.duel
        local b = self.board
        b.pos = d:pos()
        b.flipped = v == "b"
        if self.flip_mode then
            -- toutes les pièces regardent le joueur au trait
            b.flip_color = nil
            b.flip_all = self:piecesFacing() == "b"
        else
            b.flip_color = "b"
            b.flip_all = false
        end
        b.last_move = d.last
        b.selected, b.targets = self.selected, self.targets
        b.arrows, b.marks, b.badges = {}, {}, {}
        local bx = math.floor((W - self.bs) / 2)
        b:paintTo(bb, bx, ph)
        reg(bx, ph, self.bs, self.bs, function(ges)
            local sq = b:squareAt(ges.pos.x, ges.pos.y)
            if sq then self:onSquare(sq) end
        end)
    end

    function Game:draw(bb)
        local W, H = self.W, self.H
        local v = self:viewer()
        if v == "w" then
            self:drawLayout(bb, "w", function(x, y, w, h) return { x = x, y = y, w = w, h = h } end,
                function(x, y, w, h, cb) self:region(x, y, w, h, cb) end)
            return
        end
        -- au tour des Noirs : tout l'écran est tourné de 180° (comme une page qu'on retourne)
        local tmp = Blitbuffer.new(W, H, bb:getType())
        tmp:fill(UI.WHITE)
        self:drawLayout(tmp, "b",
            function(x, y, w, h) return { x = W - x - w, y = H - y - h, w = w, h = h } end,
            function(x, y, w, h, cb)
                self:region(W - x - w, H - y - h, w, h, function(ges)
                    local p = ges.pos
                    cb({ pos = { x = W - 1 - p.x, y = H - 1 - p.y } })
                end)
            end)
        local rot = tmp:rotatedCopy(180)
        bb:blitFrom(rot, 0, 0, 0, 0, W, H)
        rot:free(); tmp:free()
    end

    function Game:doMove(mv)
        local d = self.duel
        self.promo = nil
        self.panel = { w = "normal", b = "normal" }
        self.selected, self.targets = nil, nil
        if d:play(mv) then
            self:save()

            if d:ended() then return self:onEnded() end
            self:ensureTicking()
        elseif d:ended() then
            return self:onEnded()
        end
        self:refresh("ui")
    end

    function Game:onSquare(sq)
        local d = self.duel
        if d:ended() or self.promo then return end
        local mode = self.panel.w
        if mode == "pause" or mode == "menu" then return end
        local pos = d:pos()
        if self.selected and self.targets and self.targets[sq] then
            local cands = {}
            local n = 0
            for _, mv in ipairs(pos:legalMovesFrom(self.selected)) do
                if mv.to == sq then cands[mv.promo or "x"] = mv; n = n + 1 end
            end
            if n > 1 then
                self.promo = { cands = cands }
                self.panel[pos.turn] = "promo"
                self.selected, self.targets = nil, nil
                self:refresh("ui")
            elseif n == 1 then
                local _, mv = next(cands)
                self:doMove(mv)
            end
            return
        end
        local p = pos.board[sq]
        if p and Chess.colorOf(p) == pos.turn and sq ~= self.selected then
            self.selected = sq
            self.targets = {}
            for _, mv in ipairs(pos:legalMovesFrom(sq)) do self.targets[mv.to] = true end
        else
            self.selected, self.targets = nil, nil
        end
        self:refresh("ui")
    end

    function Game:rematch()
        local g = DuelMod.newGame(self.duel.g.cadence)
        self.app.data.duel = g
        self.game = g
        self.duel = Duel.new(g, self.app._clock)
        self.panel = { w = "normal", b = "normal" }
        self.selected, self.targets, self.promo = nil, nil, nil
        self:save()
        self:refresh("flashui")
    end

    return Screens
end

return DuelMod
