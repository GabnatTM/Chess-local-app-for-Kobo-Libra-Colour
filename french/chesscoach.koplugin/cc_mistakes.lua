--[[
  « Mes erreurs » : le coach reprend les erreurs et les gaffes de vos parties
  et en fait des exercices. Depuis la position juste avant l'erreur, trouvez le bon coup.

  - Recherche : les parties terminées (archive) sont analysées une à une par Stockfish,
    en tâche de fond tant que l'écran « Mes erreurs » est ouvert.
  - Un exercice est réussi avec le meilleur coup, ou avec un coup presque aussi bon
    (vérifié par Stockfish).
  - Données : data.mistakes = { list = {…}, scanned = { [id de partie] = true }, next = n }
]]

local Chess = require("cc_chess")
local Coach = require("cc_coach")

local Mistakes = {}

Mistakes.MOVETIME = 350      -- ms par position pendant la recherche
Mistakes.CHECKTIME = 1200    -- ms pour juger un autre coup que le meilleur
Mistakes.TOLERANCE = 4       -- perte tolérée (points de % de gain) pour accepter un autre coup
local KEEP = { erreur = true, manque = true, gaffe = true }

function Mistakes.ensure(d)
    d.mistakes = d.mistakes or {}
    local M = d.mistakes
    M.list = M.list or {}
    M.scanned = M.scanned or {}
    M.next = M.next or 1
    return M
end

-- Parties pas encore analysées (les plus récentes d'abord)
function Mistakes.pending(d)
    local M = Mistakes.ensure(d)
    local res = {}
    local arch = d.archive or {}
    for i = #arch, 1, -1 do
        local e = arch[i]
        if not M.scanned[e.id] and #e.moves >= 6 then res[#res + 1] = e end
    end
    return res
end

function Mistakes.counts(d)
    local M = Mistakes.ensure(d)
    local todo, done = 0, 0
    for _, mk in ipairs(M.list) do
        if mk.solved then done = done + 1 else todo = todo + 1 end
    end
    return todo, done, #M.list
end

--[[
  Analyse une partie archivée. engine:analyse est asynchrone sur la liseuse.
  cb(nouvelles_erreurs) quand c'est fini ; progress(i, n) à chaque position.
  Renvoie une fonction d'annulation.
]]
function Mistakes.scanGame(d, entry, engine, progress, cb)
    local M = Mistakes.ensure(d)
    local positions = { Chess.new(entry.start_fen or Chess.START_FEN) }
    local moves = {}
    for i, u in ipairs(entry.moves) do
        local m = positions[i]:findUci(u)
        if not m then break end
        moves[i] = m
        positions[i + 1] = positions[i]:makeMove(m)
    end
    local me = entry.player_color
    -- positions à analyser : avant chacun de vos coups, et juste après
    local need, seen = {}, {}
    for i = 1, #moves do
        if positions[i].turn == me then
            for _, k in ipairs({ i, i + 1 }) do
                if not seen[k] and not positions[k]:status() then
                    seen[k] = true
                    need[#need + 1] = k
                end
            end
        end
    end
    local lines = {}
    local cancelled = false
    local n = 0
    local function finish()
        local found = {}
        for i = 1, #moves do
            local pos = positions[i]
            if pos.turn == me and lines[i] and lines[i][1] then
                local after = positions[i + 1]
                local st = after:status()
                local after_cp
                if st then
                    after_cp = (st.result == "1/2-1/2") and 0 or 10000
                elseif lines[i + 1] and lines[i + 1][1] then
                    after_cp = -lines[i + 1][1].cp
                end
                if after_cp then
                    local cls, winB, winA = Coach.classify(pos, moves[i], lines[i], after_cp)
                    local best = lines[i][1].move
                    if KEEP[cls] and winB >= 15 and best ~= entry.moves[i] and pos:findUci(best) then
                        found[#found + 1] = {
                            id = M.next, game = entry.id, ply = i, fen = pos:fen(),
                            played = entry.moves[i], played_san = pos:san(moves[i]),
                            best = best, best_cp = lines[i][1].cp, cls = cls,
                            loss = math.floor(winB - winA + 0.5),
                            opp = entry.opp and entry.opp.name, label = entry.label, time = entry.time,
                            tries = 0,
                        }
                        M.next = M.next + 1
                    end
                end
            end
        end
        for _, mk in ipairs(found) do M.list[#M.list + 1] = mk end
        -- on garde les 300 plus récentes
        while #M.list > 300 do table.remove(M.list, 1) end
        M.scanned[entry.id] = true
        if cb then cb(found) end
    end
    local function step(k)
        if cancelled then return end
        if k > #need then return finish() end
        local idx = need[k]
        engine:analyse(positions[idx]:fen(), 1, Mistakes.MOVETIME, function(l)
            if cancelled then return end
            lines[idx] = l
            n = n + 1
            if progress then progress(n, #need) end
            step(k + 1)
        end)
    end
    step(1)
    return function() cancelled = true end
end

-- Erreurs dans l'ordre de travail : celles à réussir d'abord, les plus récentes en premier
function Mistakes.ordered(d)
    local M = Mistakes.ensure(d)
    local todo, done = {}, {}
    for i = #M.list, 1, -1 do
        local mk = M.list[i]
        if mk.solved then done[#done + 1] = mk else todo[#todo + 1] = mk end
    end
    for _, mk in ipairs(done) do todo[#todo + 1] = mk end
    return todo
end

---------------------------------------------------------------------------
-- Un exercice
---------------------------------------------------------------------------

local Ex = {}
Ex.__index = Ex
Mistakes.Exercise = Ex

function Ex.new(mk, engine, onUpdate)
    local self = setmetatable({}, Ex)
    self.mk = mk
    self.engine = engine
    self.onUpdate = onUpdate or function() end
    self.gen = 0
    self.mistakes = 0
    self:reset()
    return self
end

function Ex:reset()
    self.start = Chess.new(self.mk.fen)
    self.pos = self.start
    self.side = self.pos.turn
    self.state = "jeu"
    self.last = nil
    self.message = nil
    self.played = nil
    self.gen = self.gen + 1
end

function Ex:bestMove() return self.start:findUci(self.mk.best) end

function Ex:_good(text)
    self.state = "resolu"
    local bm = self:bestMove()
    local san = bm and self.start:san(bm) or self.mk.best
    self.message = text .. (bm and ("\n" .. Coach.moveSentence(self.start, bm, "joueur")) or "")
    if self.played ~= self.mk.best and bm then
        self.message = self.message .. "\n(Le coup de Stockfish était " .. san .. ".)"
    end
    self.onUpdate("resolu")
end

function Ex:playerMove(m)
    if self.state ~= "jeu" then return end
    local u = Chess.moveToUci(m)
    self.played = u
    self.pos = self.start:makeMove(m)
    self.last = { from = m.from, to = m.to }
    local st = self.pos:status()
    if u == self.mk.best or (st and st.result ~= "1/2-1/2") then
        return self:_good((self.mistakes == 0 and not self.helped) and "Bravo, trouvé du premier coup !" or "Bravo, c'est le bon coup !")
    end
    if u == self.mk.played then
        self.mistakes = self.mistakes + 1
        self.state = "rate"
        self.message = "C'est le coup que vous aviez joué dans la partie… Cherchez mieux ! Touchez « Réessayer »."
        return self.onUpdate("rate")
    end
    if not self.engine then
        self.mistakes = self.mistakes + 1
        self.state = "rate"
        self.message = "Ce n'est pas le meilleur coup. Touchez « Réessayer »."
        return self.onUpdate("rate")
    end
    local gen = self.gen
    self.state = "attente"
    self.message = "Le coach vérifie votre coup…"
    self.onUpdate("attente")
    self.engine:analyse(self.pos:fen(), 1, Mistakes.CHECKTIME, function(lines)
        if gen ~= self.gen then return end
        local l = lines[1]
        if not l then
            self.state = "jeu"
            return self.onUpdate("reessai")
        end
        local loss = Coach.win(self.mk.best_cp) - Coach.win(-l.cp)
        if loss <= Mistakes.TOLERANCE then
            return self:_good("Très bien : votre coup est presque aussi bon que le meilleur !")
        end
        self.mistakes = self.mistakes + 1
        self.state = "rate"
        local how = loss >= 20 and "ce coup perd beaucoup" or (loss >= 10 and "ce coup est une erreur" or "il y a mieux")
        self.message = "Pas encore : " .. how .. ". Touchez « Réessayer »."
        self.onUpdate("rate")
    end)
end

function Ex:retry()
    local mistakes = self.mistakes
    self:reset()
    self.mistakes = mistakes
    self.onUpdate("reessai")
end

---------------------------------------------------------------------------
-- Écrans
---------------------------------------------------------------------------

function Mistakes.screens()
    local ButtonDialog = require("ui/widget/buttondialog")
    local UIManager = require("ui/uimanager")
    local Board = require("cc_board")
    local Draw = require("cc_draw")
    local UI = require("cc_ui")
    local s = UI.s
    local Screens = {}

    -------------------------------------------------------------------
    -- Accueil « Mes erreurs »
    -------------------------------------------------------------------
    local Hub = UI.Canvas:extend{ app = nil }
    Screens.Hub = Hub

    function Hub:setup()
        self.scanning = nil
        self:startScan()
    end

    function Hub:startScan()
        local app = self.app
        if not app.engine or self.closed then return end
        local list = Mistakes.pending(app.data)
        if #list == 0 then self.scanning = nil return end
        local entry = list[1]
        self.scanning = { left = #list, done = 0, total = 1, entry = entry }
        self.cancel = Mistakes.scanGame(app.data, entry, app.engine, function(i, n)
            if self.closed then return end
            self.scanning.done, self.scanning.total = i, n
            if i % 6 == 0 then self:refresh("fast") end
        end, function()
            app:save()
            if self.closed then return end
            self:refresh("ui")
            self:startScan()
        end)
    end

    function Hub:stopScan()
        if self.cancel then self.cancel() end
        self.cancel = nil
        if self.app.engine then self.app.engine:cancelAll() end
        self.scanning = nil
    end

    function Hub:onClose() self:stopScan() end

    function Hub:draw(bb)
        local app = self.app
        local W = self.W
        local m = s(18)
        local y = self:header(bb, "Mes erreurs à retravailler", "Retour", function() self:close() end)
        y = y + s(14)
        local todo, done, total = Mistakes.counts(app.data)
        local intro = "Le coach reprend les erreurs (?) et les gaffes (??) de vos parties terminées. "
            .. "Depuis la position juste avant l'erreur, à vous de trouver le bon coup !"
        for _, l in ipairs(UI.wrap(UI.face(15), intro, W - 2 * m)) do
            UI.text(bb, UI.face(15), l, m, y, UI.DIM)
            y = y + UI.lineHeight(UI.face(15))
        end
        y = y + s(10)
        local tw = UI.text(bb, UI.face(34, true), tostring(todo), m, y)
        UI.text(bb, UI.face(15), (todo > 1 and "positions à retravailler" or "position à retravailler")
            .. " · " .. done .. " réussie" .. (done > 1 and "s" or ""), m + tw + s(12), y + s(14), UI.DIM)
        y = y + UI.lineHeight(UI.face(34, true)) + s(6)

        -- analyse en cours
        local sc = self.scanning
        if sc then
            local txt = "Le coach analyse vos parties : encore " .. sc.left .. (sc.left > 1 and " parties" or " partie")
                .. " (" .. math.floor(100 * sc.done / math.max(1, sc.total)) .. " % de celle-ci)…"
            UI.text(bb, UI.face(14), UI.ellipsize(UI.face(14), txt, W - 2 * m), m, y, UI.GRAY)
            y = y + UI.lineHeight(UI.face(14)) + s(2)
            local bw = W - 2 * m
            bb:paintBorder(m, y, bw, s(10), 1, UI.GRAY, s(5))
            local fw = math.floor((bw - 4) * sc.done / math.max(1, sc.total))
            if fw > 0 then Draw.roundedRect(bb, m + 2, y + 2, fw, s(6), s(3), UI.BLUE, 0x80) end
            y = y + s(24)
        elseif #(app.data.archive or {}) == 0 then
            UI.text(bb, UI.face(14), "Jouez d'abord quelques parties : elles apparaîtront ici une fois terminées.", m, y, UI.GRAY)
            y = y + s(30)
        else
            UI.text(bb, UI.face(14), "Toutes vos parties terminées ont été analysées.", m, y, UI.GRAY)
            y = y + s(30)
        end

        -- bouton principal
        local list = Mistakes.ordered(app.data)
        local bw = s(300)
        if #list > 0 then
            local lbl = todo > 0 and "Commencer l'entraînement" or "Revoir mes erreurs"
            UI.pill(bb, (W - bw) / 2, y, bw, s(48), lbl, UI.face(17, true), { dark = true })
            self:region((W - bw) / 2, y, bw, s(48), function() app:openMistake(1) end)
            y = y + s(66)
        end

        -- liste des dernières erreurs
        local f, fs = UI.face(15, true), UI.face(13)
        local rowh = s(54)
        for i, mk in ipairs(list) do
            if y + rowh > self.H - s(10) then break end
            local cat = Coach.CATEGORIES[mk.cls]
            local bs = s(30)
            Draw.disc(bb, m + bs / 2, y + rowh / 2, bs / 2, cat and cat.color, cat and cat.gray or 0xB0)
            Draw.textCentered(bb, UI.face(12, true), cat and cat.symbol or "?", m + bs / 2, y + rowh / 2, UI.BLACK, true)
            local pos = Chess.new(mk.fen)
            local num = pos.fullmove .. (pos.turn == "w" and ". " or "… ") .. (mk.played_san or "")
            UI.text(bb, f, num .. "  " .. (mk.solved and "✓" or ""), m + bs + s(12), y + s(6))
            local sub = "contre " .. (mk.opp or "?") .. (mk.label and (" · " .. mk.label) or "")
                .. (mk.time and (" · " .. os.date("%d/%m", mk.time)) or "")
            UI.text(bb, fs, UI.ellipsize(fs, sub, W - 2 * m - bs - s(12)), m + bs + s(12), y + s(30), UI.GRAY)
            bb:paintRect(m, y + rowh - 1, W - 2 * m, 1, UI.LIGHT)
            self:region(0, y, W, rowh, function() app:openMistake(i) end)
            y = y + rowh
        end
    end

    -------------------------------------------------------------------
    -- Exercice
    -------------------------------------------------------------------
    local ExScreen = UI.Canvas:extend{ app = nil, index = 1 }
    Screens.Exercise = ExScreen

    function ExScreen:setup()
        self.mg = s(6)
        self.tool_h = s(46)
        local head = s(40) + s(30)
        local panel = s(64)
        local bs = math.min(self.W, self.H - head - self.tool_h - panel)
        bs = bs - bs % 8
        self.board = Board:new{ size = bs }
        self:load(self.index)
    end

    function ExScreen:load(i)
        local list = Mistakes.ordered(self.app.data)
        self.list = list
        if #list == 0 then self.ex = nil return end
        if i < 1 then i = #list elseif i > #list then i = 1 end
        self.index = i
        self.selected, self.targets, self.arrow, self.mark = nil, nil, nil, nil
        self.hint_stage = 0
        self.show_solution = false
        self.ex = Ex.new(list[i], self.app.engine, function(ev) self:onEx(ev) end)
    end

    function ExScreen:onClose()
        if self.ex then self.ex.gen = self.ex.gen + 1 end
        if self.app.engine then self.app.engine:cancelAll() end
        if self.onDone then self.onDone() end
    end

    function ExScreen:onEx(ev)
        if self.closed then return end
        local mk = self.ex.mk
        if ev == "resolu" then
            mk.tries = (mk.tries or 0) + 1
            if self.ex.mistakes == 0 and not self.show_solution and self.hint_stage == 0 then
                mk.solved = true
            end
            mk.last = os.time()
            self.app:save()
        elseif ev == "rate" then
            mk.tries = (mk.tries or 0) + 1
            self.app:save()
        end
        self.arrow, self.mark = nil, nil
        self:refresh("ui")
    end

    function ExScreen:draw(bb)
        local W, mg = self.W, self.mg
        local y = self:header(bb, "Mes erreurs · " .. self.index .. " / " .. #self.list, "Retour", function() self:close() end)
        local ex = self.ex
        if not ex then
            UI.textCentered(bb, UI.face(16), "Aucune erreur à retravailler pour l'instant.", W / 2, y + s(40), UI.DIM)
            return
        end
        local mk = ex.mk
        local side = ex.side == "w" and "Les Blancs" or "Les Noirs"
        local info = side .. " jouent : trouvez le bon coup"
        UI.textCentered(bb, UI.face(16, true), info, W / 2, y + s(2))
        if mk.solved then UI.textRight(bb, UI.face(13), "✓ réussi", W - mg * 3, y + s(5), UI.DIM) end
        y = y + s(28)

        local b = self.board
        b.pos = ex.pos
        b.flipped = ex.side == "b"
        b.last_move = ex.last
        b.selected, b.targets = self.selected, self.targets
        b.arrows, b.marks, b.badges = {}, {}, {}
        if self.arrow then b.arrows[1] = self.arrow end
        if self.mark then b.marks[1] = self.mark end
        if ex.state == "rate" and ex.last then
            b.badges[1] = { sq = ex.last.to, cat = "erreur", big = true }
        elseif ex.state == "resolu" and ex.last then
            b.badges[1] = { sq = ex.last.to, cat = "meilleur", big = true }
        end
        local bx = math.floor((W - b.size) / 2)
        b:paintTo(bb, bx, y)
        self:region(bx, y, b.size, b.size, function(ges)
            local sq = b:squareAt(ges.pos.x, ges.pos.y)
            if sq then self:onSquare(sq) end
        end)
        y = y + b.size + s(4)

        local items
        if ex.state == "resolu" then
            items = {
                { "‹ Préc.", function() self:go(-1) end },
                { "Jouer d'ici contre l'IA", function() self:playOn() end },
                { "Suivant ›", function() self:go(1) end, true },
            }
        elseif ex.state == "rate" then
            items = {
                { "‹ Préc.", function() self:go(-1) end },
                { "Réessayer", function() ex:retry() end, true },
                { "Solution", function() self:solution() end },
                { "Suiv. ›", function() self:go(1) end },
            }
        else
            items = {
                { "‹ Préc.", function() self:go(-1) end },
                { "Indice", function() self:hint() end },
                { "Solution", function() self:solution() end },
                { "Suiv. ›", function() self:go(1) end },
            }
        end
        local f = UI.face(17)
        local widths, total = {}, 0
        for i, it in ipairs(items) do
            widths[i] = UI.textWidth(f, it[1]) + s(26)
            total = total + widths[i]
        end
        local gap = math.max(s(4), math.floor((W - total) / (#items + 1)))
        local x = gap
        for i, it in ipairs(items) do
            UI.pill(bb, x, y + s(4), widths[i], self.tool_h - s(8), it[1], f, it[3] and { dark = true } or {})
            self:region(x - gap / 2, y, widths[i] + gap, self.tool_h, it[2])
            x = x + widths[i] + gap
        end
        y = y + self.tool_h + s(6)

        local cat = Coach.CATEGORIES[mk.cls]
        local pos = ex.start
        local where = "Partie contre " .. (mk.opp or "?") .. (mk.label and (" (" .. mk.label .. ")") or "")
            .. ", coup " .. pos.fullmove .. ". "
        local text
        if ex.state == "attente" then
            text = ex.message
        elseif ex.message then
            text = ex.message
        else
            text = where .. "Vous aviez joué " .. (mk.played_san or "?") .. " (" .. (cat and cat.label:lower() or "erreur")
                .. ", vous perdiez environ " .. (mk.loss or "?") .. " % de chances de gain). Trouvez mieux !"
        end
        if self.show_solution and ex.state ~= "resolu" then
            local bm = ex:bestMove()
            if bm then text = text .. "\n\nLe bon coup : " .. pos:san(bm) .. ". " .. Coach.moveSentence(pos, bm, "joueur") end
        end
        local px = mg * 3
        if text ~= self._last_text then self._last_text = text; self.page = 1 end
        self:pagedText(bb, UI.face(15), text, px, y, W - 2 * px)
    end

    function ExScreen:go(dir)
        if self.ex then self.ex.gen = self.ex.gen + 1 end
        if self.app.engine then self.app.engine:cancelAll() end
        self:load(self.index + dir)
        self:refresh("ui")
    end
    function ExScreen:onPrevKey() self:go(-1) end
    function ExScreen:onNextKey() self:go(1) end
    function ExScreen:onSwipe(dir)
        if dir == "east" then self:go(-1) elseif dir == "west" then self:go(1) end
    end

    function ExScreen:hint()
        local ex = self.ex
        if not ex or ex.state ~= "jeu" then return end
        local bm = ex:bestMove()
        if not bm then return end
        self.hint_stage = self.hint_stage + 1
        ex.helped = true
        if self.hint_stage == 1 then
            local vague = Coach.hint(ex.start, { { move = ex.mk.best, cp = ex.mk.best_cp } })
            self.mark = { sq = bm.from, rgb = UI.GOLD, gray = 0xC8 }
            ex.message = (vague or "La pièce à jouer est marquée.") .. " Touchez encore « Indice » pour voir le coup."
        else
            self.mark = nil
            self.arrow = { from = bm.from, to = bm.to, rgb = Coach.BEST_ARROW, gray = 0x60 }
            ex.message = "Le coup à jouer : " .. ex.start:san(bm) .. "."
        end
        self:refresh("ui")
    end

    function ExScreen:solution()
        local ex = self.ex
        if not ex then return end
        if ex.state == "rate" then ex:retry() end
        self.show_solution = true
        ex.helped = true
        local bm = ex:bestMove()
        if bm then self.arrow = { from = bm.from, to = bm.to, rgb = Coach.BEST_ARROW, gray = 0x60 } end
        ex.message = nil
        self:refresh("ui")
    end

    function ExScreen:playOn()
        local ex = self.ex
        if not ex then return end
        self.app:playFromPosition(ex.mk.fen, ex.side, "Entraînement — " .. (ex.mk.opp and ("partie contre " .. ex.mk.opp) or "mes erreurs"))
    end

    function ExScreen:onSquare(sq)
        local ex = self.ex
        if not ex or ex.state ~= "jeu" then return end
        local pos = ex.pos
        if self.selected and self.targets and self.targets[sq] then
            local cands = {}
            for _, mv in ipairs(pos:legalMovesFrom(self.selected)) do
                if mv.to == sq then cands[#cands + 1] = mv end
            end
            self.selected, self.targets = nil, nil
            self.arrow, self.mark = nil, nil
            if #cands > 1 then
                local dialog
                local names = { q = "Dame", r = "Tour", b = "Fou", n = "Cavalier" }
                local row = {}
                for _, pr in ipairs({ "q", "r", "b", "n" }) do
                    for _, mv in ipairs(cands) do
                        if mv.promo == pr then
                            row[#row + 1] = { text = names[pr], callback = function()
                                UIManager:close(dialog)
                                ex.message = nil
                                ex:playerMove(mv)
                                self:refresh("ui")
                            end }
                        end
                    end
                end
                dialog = ButtonDialog:new{ title = "Promotion du pion", buttons = { row } }
                UIManager:show(dialog)
            elseif #cands == 1 then
                ex.message = nil
                ex:playerMove(cands[1])
                self:refresh("ui")
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

    return Screens
end

return Mistakes
