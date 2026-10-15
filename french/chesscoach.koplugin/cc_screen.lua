--[[
  L'écran de partie (tous les modes).
  - Coach : interface minimaliste ; l'ampoule ouvre l'avis du coach,
    ‹ › (ou les boutons de page de la liseuse) parcourent la partie.
  - Partie à la pendule : deux pendules, pas d'aide, pas de retour en arrière.
]]

local ButtonDialog = require("ui/widget/buttondialog")
local ConfirmBox = require("ui/widget/confirmbox")
local Geom = require("ui/geometry")
local InfoMessage = require("ui/widget/infomessage")
local SpinWidget = require("ui/widget/spinwidget")
local UIManager = require("ui/uimanager")

local AI = require("cc_ai")
local Board = require("cc_board")
local Chess = require("cc_chess")
local Coach = require("cc_coach")
local Draw = require("cc_draw")
local Lamp = require("cc_lamp")
local UI = require("cc_ui")

local GameScreen = UI.Canvas:extend{
    match = nil,
    actions = nil,   -- { exit(), newGame(), bilan(), profile, exit_label }
}

local s = UI.s

function GameScreen:setup()
    local m = self.match
    self.coach = m:isCoach()
    self.named = not self.coach
    self.flipped = m.g.player_color == "b"
    self.mode = "live"
    self.hint_stage = 0
    self.show_eval = false
    self.page = 1
    self.mg = s(6)
    self.row_h = s(30)
    self.eval_h = s(20)
    self.tool_h = s(42)
    local rows = self.named and 2 * self.row_h or self.row_h
    local panel_min = self.coach and s(125) or s(70)
    local bs = math.min(self.W - 2 * self.mg, self.H - rows - self.eval_h - self.tool_h - panel_min - 2 * self.mg)
    self.board_full = Board:new{ size = bs }
    -- échiquier plus petit quand le coach parle, pour laisser de la place au texte
    self.board_small = Board:new{ size = math.floor(bs * 0.8) }
    self.board = self.board_full
    self.lamp = Lamp:new{ size = self.tool_h }
    self.f_small = UI.face(14)
    self.f_row = UI.face(15)
    self.f_row_b = UI.face(15, true)
    self.f_tool = UI.face(17)
    self.f_text = UI.face(16)
    self.f_clock = UI.face(20, true)
    m.onUpdate = function(ev) self:onMatchUpdate(ev) end
end

function GameScreen:onClose()
    self.match:pause()
    self.match.onUpdate = function() end
end

function GameScreen:onSuspend() self.match:pause() end
function GameScreen:onResume()
    if not self.closed then
        self.match:resume()
        self:refresh("ui")
    end
end

---------------------------------------------------------------------------
-- Événements de la partie
---------------------------------------------------------------------------

function GameScreen:onMatchUpdate(ev)
    if self.closed then return end
    if ev == "clock" then
        if self.clock_rect then self:refresh("fast", self.clock_rect) end
        return
    end
    if ev == "move" or ev == "nav" then
        self.selected, self.targets = nil, nil
        self.page = 1
        if ev == "move" and self.mode == "hint" then self.mode = "live" end
    end
    if ev == "analysis" and self.mode == "live" and not self.show_eval then
        return -- rien de visible n'a changé
    end
    self:refresh("ui")
    if ev == "gameover" then
        local token = {}
        self.gameover_token = token
        UIManager:scheduleIn(1.5, function()
            if self.closed or self.gameover_token ~= token then return end
            if self.actions and self.actions.bilan then self.actions.bilan() end
        end)
    end
end

---------------------------------------------------------------------------
-- Ce qu'on affiche
---------------------------------------------------------------------------

-- index de la position affichée (nombre de coups joués)
function GameScreen:displayIdx()
    if self.mode == "coach" then return math.max(0, (self.coach_ply or 1) - 1) end
    return self.match.g.cursor
end

function GameScreen:syncBoard()
    local b = self.board
    local m = self.match
    local g = m.g
    b.flipped = self.flipped
    b.arrows, b.badges, b.marks = {}, {}, {}
    b.selected, b.targets, b.last_move, b.premove = nil, nil, nil, nil
    self.lamp.rgb, self.lamp.gray, self.lamp.active = nil, 0xFF, false

    if self.mode == "coach" then
        self.lamp.active = true
        local ply = self.coach_ply or 0
        if ply == 0 then
            b.pos = m.positions[1]
            return
        end
        local pos = m.positions[ply]
        b.pos = pos
        local mv = pos:findUci(g.moves[ply])
        if pos.turn == g.player_color then
            local a = m:annotation(ply)
            if a then
                local cat = Coach.CATEGORIES[a.cls]
                self.lamp.rgb, self.lamp.gray = cat.color, cat.gray
                local best = g.lines[pos:key()] and g.lines[pos:key()][1]
                if best and best.move ~= g.moves[ply] then
                    local bm = pos:findUci(best.move)
                    if bm then b.arrows[#b.arrows + 1] = { from = bm.from, to = bm.to, rgb = Coach.BEST_ARROW, gray = 0x60 } end
                end
                if mv then
                    b.arrows[#b.arrows + 1] = { from = mv.from, to = mv.to, rgb = cat.color, gray = 0xB0 }
                    b.badges[#b.badges + 1] = { sq = mv.to, cat = a.cls, big = true }
                end
                return
            end
        end
        if mv then b.arrows[#b.arrows + 1] = { from = mv.from, to = mv.to, rgb = nil, gray = 0x90 } end
        return
    end

    b.pos = m:viewPos()
    local c = g.cursor
    if c > 0 then
        local lm = m.positions[c]:findUci(g.moves[c])
        if lm then b.last_move = { from = lm.from, to = lm.to } end
    end
    if self.mode == "hint" then
        local _, hm = m:hint()
        if type(hm) == "table" then
            if self.hint_stage >= 2 then
                b.arrows[#b.arrows + 1] = { from = hm.from, to = hm.to, rgb = Coach.BEST_ARROW, gray = 0x60 }
            else
                b.marks[#b.marks + 1] = { sq = hm.from, rgb = Coach.BEST_ARROW, gray = 0xD8 }
            end
        end
        return
    end
    b.selected = self.selected
    b.targets = self.targets
    b.premove = m.premove
end

local function fmtClock(t)
    t = math.max(0, t)
    if t < 10 then
        return (string.format("0:%04.1f", math.floor(t * 10) / 10):gsub("%.", ","))
    end
    local secs = math.ceil(t - 0.001)
    return string.format("%d:%02d", math.floor(secs / 60), secs % 60)
end
GameScreen.fmtClock = fmtClock

function GameScreen:panelContent()
    local m = self.match
    local g = m.g
    if self.mode == "coach" then
        local ply = self.coach_ply or 0
        if ply == 0 then
            return nil, nil, "Début de la partie. Avancez avec › ou le bouton « page suivante » de la liseuse."
        end
        local e = m:explain(ply)
        if e then
            local cat = e.cat and Coach.CATEGORIES[e.cat]
            local title = e.title .. (cat and ("  " .. cat.symbol .. " " .. cat.label) or "")
            return title, cat, e.text
        end
    end
    if self.mode == "hint" then
        local vague, _, full = m:hint()
        if vague then
            if self.hint_stage >= 2 then
                return "Indice", { color = Coach.BEST_ARROW, gray = 0xD8 }, full .. "\nLa flèche verte montre ce coup."
            end
            return "Indice", { color = Coach.BEST_ARROW, gray = 0xD8 }, vague .. "\nTouchez encore « Indice » pour voir le coup."
        end
        return nil, nil, "Le coach réfléchit…"
    end
    if g.analysis and m:ended() then
        local done, total = m:analysisProgress()
        local head = "Analyse : " .. (g.label_short or "") .. " (" .. (g.score_text or "") .. ")"
        if done < total then
            head = head .. "\nLe coach analyse la partie : " .. done .. " / " .. total .. " de vos coups."
        else
            head = head .. "\nAnalyse terminée. Touchez l'ampoule pour les commentaires, ‹ › pour parcourir."
        end
        return nil, nil, head
    end
    if m:ended() then
        local lines = {}
        local res = m:resultText()
        if g.elo_after and g.elo_before then
            local d = g.elo_after - g.elo_before
            res = res .. string.format(" — Elo %d → %d (%s%d)", g.elo_before, g.elo_after, d >= 0 and "+" or "", d)
        end
        lines[#lines + 1] = res
        if not m:atEnd() and g.cursor > 0 and not self.coach then
            local pos = m.positions[g.cursor]
            local mv = pos:findUci(g.moves[g.cursor])
            if mv then
                local who = pos.turn == g.player_color and "joueur" or "adversaire"
                lines[#lines + 1] = Coach.moveSentence(pos, mv, who)
            end
        else
            lines[#lines + 1] = "Touchez « Bilan » pour le résumé et le graphique de la partie."
        end
        return nil, nil, table.concat(lines, "\n")
    end
    if not m:atEnd() then
        local txt = "Coup " .. g.cursor .. " sur " .. #g.moves .. "."
        if m:canPlayHere() then
            txt = txt .. " Rejouez le même coup pour suivre la partie, ou un autre coup pour la reprendre d'ici."
        else
            txt = txt .. " Avancez avec ›."
        end
        return nil, nil, txt
    end
    if m:isThinking() then
        local t = self.named and (g.opp.name .. " réfléchit…") or "L'IA réfléchit…"
        if m.premove then t = t .. " Votre coup anticipé est prêt." end
        return nil, nil, t
    end
    if m:playerToMove() then return nil, nil, "À vous de jouer." end
    return nil, nil, ""
end

---------------------------------------------------------------------------
-- Dessin
---------------------------------------------------------------------------

function GameScreen:drawClock(bb, x, y, w, h, color)
    local m = self.match
    local t = m:clock(color)
    local active = not m:ended() and m:livePos().turn == color and not m.paused
    local low = t < 30 and color == m.g.player_color
    local r = math.floor(h / 2.5)
    if active and low then
        Draw.roundedRect(bb, x, y, w, h, r, UI.RED, 0x90)
    elseif active then
        Draw.roundedRect(bb, x, y, w, h, r, nil, 0x00)
    else
        bb:paintRect(x, y, w, h, UI.WHITE)
        bb:paintBorder(x, y, w, h, s(1), UI.BLACK, r)
    end
    UI.textCentered(bb, self.f_clock, fmtClock(t), x + w / 2, y + (h - UI.lineHeight(self.f_clock)) / 2 + s(2),
        (active and not low) and UI.WHITE or UI.BLACK)
end

function GameScreen:drawPlayerRow(bb, y, isOpp)
    local m = self.match
    local g = m.g
    local x0 = self.mg * 2
    local h = self.row_h
    local name, info, color
    if isOpp then
        name = g.opp.name
        info = g.opp.elo .. " · " .. AI.persona(g.opp.persona).name
        color = m:aiColor()
    else
        name = "Vous"
        info = tostring(self.actions.profile.player_elo)
        color = g.player_color
    end
    local sq = s(12)
    local yy = y + math.floor((h - sq) / 2)
    bb:paintRect(x0, yy, sq, sq, color == "w" and UI.WHITE or UI.BLACK)
    bb:paintBorder(x0, yy, sq, sq, 1, UI.BLACK)
    local tx = x0 + sq + s(8)
    local ty = y + (h - UI.lineHeight(self.f_row)) / 2 + s(2)
    local w = UI.text(bb, self.f_row_b, name, tx, ty)
    UI.text(bb, self.f_row, "  " .. info, tx + w, ty, UI.DIM)
    if m:isTimed() then
        local cw, ch = s(92), h - s(4)
        local cx = self.W - self.mg * 2 - cw
        local cy = y + s(2)
        self:drawClock(bb, cx, cy, cw, ch, color)
        return { x = cx, y = cy, w = cw, h = ch }
    end
end

function GameScreen:drawEvalBar(bb, y)
    local m = self.match
    local x, w, h = self.mg * 2, self.W - self.mg * 4, self.eval_h - s(6)
    y = y + s(3)
    local idx = self:displayIdx()
    local cp = m:evalAt(idx)
    if cp == nil then
        m:requestEval(idx)
        bb:paintBorder(x, y, w, h, 1, UI.GRAY)
        UI.textCentered(bb, self.f_small, "évaluation…", x + w / 2, y + (h - UI.lineHeight(self.f_small)) / 2 + 1, UI.GRAY)
        return
    end
    local win = AI.winPercent(cp) / 100
    local ww = math.floor(w * win + 0.5)
    bb:paintRect(x, y, w, h, UI.BLACK)
    bb:paintRect(x + 1, y + 1, math.max(0, ww - 1), h - 2, UI.WHITE)
    bb:paintRect(x + math.floor(w / 2), y, 1, h, UI.GRAY)
    local label
    if cp >= 9000 then label = "Mat pour les blancs"
    elseif cp <= -9000 then label = "Mat pour les noirs"
    else label = (string.format("%+.1f", cp / 100):gsub("%.", ",")) end
    local f = UI.face(11, true)
    local ty = y + (h - f.size) / 2 - f.size * 0.12
    if cp >= 0 then
        UI.text(bb, f, label, x + s(6), ty, UI.BLACK)
    else
        UI.textRight(bb, f, label, x + w - s(6), ty, UI.WHITE)
    end
end

function GameScreen:toolbarItems()
    local m = self.match
    local items = {}
    local function add(label, cb, opts)
        opts = opts or {}
        items[#items + 1] = { label = label, cb = cb, hold = opts.hold, enabled = opts.enabled ~= false,
            active = opts.active, big = opts.big }
    end
    if self.coach then items[#items + 1] = { lamp = true } end
    if self.mode == "coach" then
        add("‹", function() self:nav(-1) end, { hold = function() self:navTo(1) end, big = true,
            enabled = (self.coach_ply or 1) > 1 })
        add("›", function() self:nav(1) end, { hold = function() self:navTo(#m.g.moves) end, big = true,
            enabled = (self.coach_ply or 0) < #m.g.moves })
    elseif m:canNavigate() then
        add("‹", function() self:nav(-1) end, { hold = function() self:navTo(0) end, big = true,
            enabled = m.g.cursor > 0 })
        add("›", function() self:nav(1) end, { hold = function() self:navTo(#m.g.moves) end, big = true,
            enabled = not m:atEnd() })
    end
    if self.coach and not m:ended() then
        add("Indice", function() self:showHint() end, { active = self.mode == "hint" })
    end
    if m:canUseEval() then
        add("Éval", function()
            self.show_eval = not self.show_eval
            self:refresh("ui")
        end, { active = self.show_eval })
    end
    if not self.coach and not m:ended() then
        add("Nulle ?", function() self:offerDraw() end)
        add("Abandon", function() self:askResign() end)
    end
    if m:ended() then
        add("Bilan", function() if self.actions.bilan then self.actions.bilan() end end)
    end
    add("Menu", function() self:showMenu() end)
    return items
end

function GameScreen:draw(bb)
    local m = self.match
    local g = m.g
    local W, mg = self.W, self.mg
    if self.coach_ply and self.coach_ply > #g.moves then self.coach_ply = #g.moves end
    if self.mode == "coach" and #g.moves == 0 then self.mode = "live" end
    local small = self.mode == "coach" or self.mode == "hint"
    self.board = small and self.board_small or self.board_full
    self:syncBoard()
    local y = 0
    self.clock_rect = nil
    local rects = {}
    -- l'adversaire est en haut quand l'échiquier est dans le sens du joueur
    local oppOnTop = (self.flipped == (g.player_color == "b"))

    if self.named then
        rects[#rects + 1] = self:drawPlayerRow(bb, y, oppOnTop)
    else
        local ty = (self.row_h - UI.lineHeight(self.f_row)) / 2 + s(2)
        local w = UI.text(bb, self.f_row_b, "Vous", mg * 2, ty)
        UI.text(bb, self.f_row, "  " .. self.actions.profile.player_elo, mg * 2 + w, ty, UI.DIM)
        local right = g.analysis and ("Analyse · " .. (g.label_short or ""))
            or ("IA " .. g.opp.elo .. " · " .. AI.styleById(g.opp.style).name)
        UI.textRight(bb, self.f_row, UI.ellipsize(self.f_row, right, W * 0.7), W - mg * 2, ty, UI.DIM)
    end
    y = y + self.row_h

    local bx = math.floor((W - self.board.size) / 2)
    if small then
        -- garder la même hauteur de rangée d'outils que l'échiquier plein : on remonte le texte
        self.board:paintTo(bb, bx, y)
    else
        self.board:paintTo(bb, bx, y)
    end
    self:region(bx, y, self.board.size, self.board.size, function(ges)
        local sq = self.board:squareAt(ges.pos.x, ges.pos.y)
        if sq then self:onSquare(sq) end
    end)
    y = y + self.board.size

    if self.show_eval and m:canUseEval() then self:drawEvalBar(bb, y) end
    y = y + self.eval_h

    if self.named then
        rects[#rects + 1] = self:drawPlayerRow(bb, y, not oppOnTop)
        y = y + self.row_h
    end
    if #rects == 2 then
        local r1, r2 = rects[1], rects[2]
        self.clock_rect = Geom:new{ x = r1.x, y = r1.y, w = r1.w, h = r2.y + r2.h - r1.y }
    end

    -- barre d'outils
    local items = self:toolbarItems()
    local widths, total = {}, 0
    for i, it in ipairs(items) do
        if it.lamp then
            widths[i] = self.tool_h
        else
            local f = it.big and UI.face(24) or self.f_tool
            widths[i] = UI.textWidth(f, it.label) + s(it.big and 24 or 12)
        end
        total = total + widths[i]
    end
    local gap = math.max(0, math.floor((W - total) / (#items + 1)))
    local x = gap
    for i, it in ipairs(items) do
        local w = widths[i]
        if it.lamp then
            self.lamp:paintTo(bb, x, y)
            self:region(x - gap / 2, y, w + gap, self.tool_h, function() self:toggleCoach() end)
        else
            local f = it.big and UI.face(24) or self.f_tool
            local ty = y + (self.tool_h - UI.lineHeight(f)) / 2 + s(2)
            UI.textCentered(bb, f, it.label, x + w / 2, ty, it.enabled and UI.BLACK or UI.LIGHT)
            if it.active then
                bb:paintRect(x + s(6), ty + UI.lineHeight(f) - s(2), w - s(12), s(2), UI.BLACK)
            end
            if it.enabled then
                self:region(x - gap / 2, y, w + gap, self.tool_h, it.cb, it.hold)
            end
        end
        x = x + w + gap
    end
    y = y + self.tool_h

    -- zone de texte
    local title, cat, text = self:panelContent()
    local px = mg * 3
    local pw = W - px * 2
    local top = y
    if title then
        local f = UI.face(14, true)
        local tw = math.min(pw, UI.textWidth(f, title) + s(22))
        local th = s(22)
        Draw.roundedRect(bb, px, y, tw, th, math.floor(th / 2), cat and cat.color or nil, cat and cat.gray or 0xE8)
        UI.textCentered(bb, f, title, px + tw / 2, y + (th - UI.lineHeight(f)) / 2 + s(1))
        y = y + th + s(6)
    end
    local lh = UI.lineHeight(self.f_text)
    local lines = UI.wrap(self.f_text, text or "", pw)
    local fit = math.max(1, math.floor((self.H - y - mg) / lh))
    if #lines > fit then
        fit = math.max(1, math.floor((self.H - y - mg - UI.lineHeight(self.f_small)) / lh))
    end
    local pages = math.max(1, math.ceil(#lines / fit))
    if self.page > pages then self.page = 1 end
    local first = (self.page - 1) * fit + 1
    for i = first, math.min(#lines, first + fit - 1) do
        UI.text(bb, self.f_text, lines[i], px, y)
        y = y + lh
    end
    if pages > 1 then
        UI.textRight(bb, self.f_small, "suite " .. self.page .. "/" .. pages .. " ▸", W - px,
            self.H - UI.lineHeight(self.f_small) - s(2), UI.GRAY)
        self:region(0, top, W, self.H - top, function()
            self.page = self.page % pages + 1
            self:refresh("ui")
        end)
    end
end

---------------------------------------------------------------------------
-- Actions
---------------------------------------------------------------------------

function GameScreen:nav(dir)
    if self.mode == "coach" then
        return self:navTo((self.coach_ply or 1) + dir)
    end
    if self.match:canNavigate() then self.match:step(dir) end
end

function GameScreen:navTo(idx)
    if self.mode == "coach" then
        local n = #self.match.g.moves
        idx = math.max(1, math.min(n, idx))
        if idx ~= self.coach_ply then
            self.coach_ply = idx
            self.page = 1
            self:refresh("ui")
        end
        return
    end
    if self.match:canNavigate() then self.match:goTo(idx) end
end

function GameScreen:onPrevKey() self:nav(-1) end
function GameScreen:onNextKey() self:nav(1) end
function GameScreen:onSwipe(dir)
    if dir == "east" then self:nav(-1) elseif dir == "west" then self:nav(1) end
end

function GameScreen:onSquare(sq)
    local m = self.match
    if self.mode == "coach" then
        self.mode = "live"
        self:refresh("ui")
        return
    end
    if self.mode == "hint" then self.mode = "live" end
    if not m:canPlayHere() and m:premoveAllowed() then
        return self:premoveTap(sq)
    end
    if not m:canPlayHere() then
        if self.selected then
            self.selected, self.targets = nil, nil
            self:refresh("ui")
        end
        return
    end
    local pos = m:viewPos()
    if self.selected and self.targets and self.targets[sq] then
        local cands = {}
        for _, mv in ipairs(pos:legalMovesFrom(self.selected)) do
            if mv.to == sq then cands[#cands + 1] = mv end
        end
        self.selected, self.targets = nil, nil
        if #cands > 1 then
            self:askPromotion(cands)
        elseif #cands == 1 then
            m:playerMove(cands[1])
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
    self:refresh("ui", Geom:new{ x = self.board.dimen.x, y = self.board.dimen.y,
        w = self.board.size, h = self.board.size })
end

-- Préparer un coup pendant que l'adversaire réfléchit
function GameScreen:premoveTap(sq)
    local m = self.match
    local pos = m:livePos()
    local mine = m.g.player_color
    if self.selected and self.targets and self.targets[sq] then
        m:setPremove(self.selected, sq)
        self.selected, self.targets = nil, nil
    else
        local p = pos.board[sq]
        if p and Chess.colorOf(p) == mine and sq ~= self.selected then
            m:clearPremove()
            self.selected = sq
            self.targets = pos:premoveTargets(sq)
        else
            m:clearPremove()
            self.selected, self.targets = nil, nil
        end
    end
    self:refresh("ui", Geom:new{ x = self.board.dimen.x, y = self.board.dimen.y,
        w = self.board.size, h = self.board.size })
end

function GameScreen:askPromotion(cands)
    local dialog
    local names = { q = "Dame", r = "Tour", b = "Fou", n = "Cavalier" }
    local row = {}
    for _, pr in ipairs({ "q", "r", "b", "n" }) do
        for _, mv in ipairs(cands) do
            if mv.promo == pr then
                row[#row + 1] = { text = names[pr], callback = function()
                    UIManager:close(dialog)
                    self.match:playerMove(mv)
                end }
            end
        end
    end
    dialog = ButtonDialog:new{ title = "Promotion du pion", buttons = { row } }
    UIManager:show(dialog)
end

function GameScreen:toggleCoach()
    if self.mode == "coach" then
        self.mode = "live"
    else
        if #self.match.g.moves == 0 then
            UIManager:show(InfoMessage:new{ text = "Jouez un coup : le coach le commentera quand vous toucherez l'ampoule.", timeout = 3 })
            return
        end
        self.mode = "coach"
        self.selected, self.targets = nil, nil
        -- on ouvre sur votre dernier coup (jusqu'à la position affichée)
        local g = self.match.g
        local ply = math.max(1, g.cursor)
        for i = ply, 1, -1 do
            if self.match.positions[i].turn == g.player_color then ply = i break end
        end
        self.coach_ply = ply
    end
    self.page = 1
    self:refresh("ui")
end

function GameScreen:showHint()
    local m = self.match
    local vague, mv = m:hint()
    if not vague then
        if mv == "pending" then
            UIManager:show(InfoMessage:new{ text = "Le coach réfléchit encore, réessayez dans un instant.", timeout = 2 })
        end
        return
    end
    if self.mode == "hint" then
        self.hint_stage = 2
    else
        self.mode = "hint"
        self.hint_stage = 1
    end
    self.selected, self.targets = nil, nil
    self.page = 1
    self:refresh("ui")
end

function GameScreen:offerDraw()
    local m = self.match
    local r = m:offerDraw()
    local name = m.g.opp.name
    if r == nil then
        UIManager:show(InfoMessage:new{ text = "Vous avez déjà proposé nulle il y a peu.", timeout = 2 })
    elseif r == false then
        UIManager:show(InfoMessage:new{ text = name .. " refuse la nulle et continue à jouer.", timeout = 2 })
    end
end

function GameScreen:askResign()
    UIManager:show(ConfirmBox:new{
        text = "Abandonner cette partie ?",
        ok_text = "Abandonner", cancel_text = "Continuer",
        ok_callback = function() self.match:resign() end,
    })
end

function GameScreen:showMenu()
    local m = self.match
    local p = self.actions.profile
    local dialog
    local function item(text, cb)
        return { { text = text, align = "left", callback = function()
            UIManager:close(dialog)
            cb()
        end } }
    end
    local buttons = {}
    if self.coach then
        buttons[#buttons + 1] = item("Nouvelle partie", function() self.actions.newGame() end)
        buttons[#buttons + 1] = item("Niveau de l'IA : " .. m.g.opp.elo .. " Elo", function() self:askElo() end)
        buttons[#buttons + 1] = item("Style de l'IA : " .. AI.styleById(m.g.opp.style).name, function() self:askStyle() end)
        buttons[#buttons + 1] = item((string.format("Temps d'analyse : %.1f s", p.think_ms / 1000):gsub("%.", ",")),
            function() self:askThink() end)
        if self.actions.archive then
            buttons[#buttons + 1] = item("Analyser une partie jouée", function() self.actions.archive() end)
        end
    elseif m:ended() and self.actions.newGame then
        buttons[#buttons + 1] = item("Nouvelle partie", function() self.actions.newGame() end)
    end
    buttons[#buttons + 1] = item("Retourner l'échiquier", function()
        self.flipped = not self.flipped
        self:refresh("ui")
    end)
    local back = self.actions.exit_label or "Menu principal"
    if not self.coach and not m:ended() then back = back .. " (partie en pause)" end
    buttons[#buttons + 1] = item(back, function() self.actions.exit() end)
    dialog = ButtonDialog:new{ title = m.g.label or (self.coach and "Coach d'échecs" or "Partie"), buttons = buttons }
    UIManager:show(dialog)
end

function GameScreen:askElo()
    local m = self.match
    UIManager:show(SpinWidget:new{
        title_text = "Niveau de l'IA (Elo)",
        info_text = "400 : débutant\n1000 : joueur occasionnel\n1500 : bon joueur de club\n2000 : expert\n2500 : maître",
        value = m.g.opp.elo, value_min = AI.MIN_ELO, value_max = AI.MAX_ELO,
        value_step = 50, value_hold_step = 200, ok_text = "Valider", cancel_text = "Annuler",
        callback = function(spin)
            m.g.opp.elo = spin.value
            m.g.opp.name = "IA " .. spin.value
            self.actions.profile.ai_elo = spin.value
            m:save()
            self:refresh("ui")
        end,
    })
end

function GameScreen:askStyle()
    local m = self.match
    local dialog
    local buttons, desc = {}, {}
    for _, st in ipairs(AI.STYLES) do
        desc[#desc + 1] = st.name .. " : " .. st.desc
        buttons[#buttons + 1] = { {
            text = st.name .. (st.id == m.g.opp.style and "  ✓" or ""),
            callback = function()
                UIManager:close(dialog)
                m.g.opp.style = st.id
                self.actions.profile.style = st.id
                m:save()
                self:refresh("ui")
            end,
        } }
    end
    dialog = ButtonDialog:new{ title = table.concat(desc, "\n"), buttons = buttons }
    UIManager:show(dialog)
end

function GameScreen:askThink()
    local p = self.actions.profile
    UIManager:show(SpinWidget:new{
        title_text = "Temps d'analyse par coup",
        info_text = "Plus long = coach plus précis, mais plus d'attente et de batterie.",
        value = p.think_ms / 1000, value_min = 0.5, value_max = 5, value_step = 0.5, value_hold_step = 1,
        precision = "%.1f", ok_text = "Valider", cancel_text = "Annuler",
        callback = function(spin)
            p.think_ms = math.floor(spin.value * 1000 + 0.5)
            self.match:save()
        end,
    })
end

return GameScreen
