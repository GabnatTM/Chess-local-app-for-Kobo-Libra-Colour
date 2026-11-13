--[[
  Problèmes de mat (László Polgár, « Chess: 5334 Problems, Combinations and Games »).
  4462 problèmes : mat en 1 (n° 1 à 306), mat en 2 (n° 307 à 3718), mat en 3 (n° 3719 à 4462).

  - La logique (Puzzle) est séparée des écrans pour pouvoir être testée sur ordinateur.
  - Un autre coup que celui du livre est accepté s'il mate aussi dans le bon nombre de coups
    (vérifié par Stockfish) ; la défense est alors jouée par Stockfish.
  - La progression est gardée dans les données du jeu (data.problems).
]]

local Chess = require("cc_chess")

local Problems = {}

Problems.TOTAL = 5334
Problems.CHAPTERS = {
    { id = "m1",     first = 1,    last = 306,  name = "Mat en 1 coup" },
    { id = "m2w",    first = 307,  last = 450,  name = "Mat en 2 coups" },
    { id = "c2",     first = 451,  last = 3514, name = "Combinaisons : mat en 2" },
    { id = "c2b",    first = 3515, last = 3718, name = "Combinaisons : mat en 2 (suite)" },
    { id = "c3",     first = 3719, last = 4462, name = "Combinaisons : mat en 3" },
    { id = "games",  first = 4463, last = 5062, name = "600 parties miniatures" },
    { id = "draw",   first = 5063, last = 5104, name = "Finales : les Blancs annulent" },
    { id = "win",    first = 5105, last = 5206, name = "Finales : les Blancs gagnent" },
    { id = "polgar", first = 5207, last = 5333, name = "Combinaisons des sœurs Polgár" },
    { id = "m2",     first = 5334, last = 5334, name = "Le dernier problème : mat en 2" },
}

local GOALS = {
    games = "jouent et gagnent : trouvez la combinaison",
    polgar = "jouent et gagnent : trouvez la combinaison",
    draw = "jouent et font nulle",
    win = "jouent et gagnent",
}

local DATA
local function data()
    if not DATA then DATA = require("cc_problems_data") end
    return DATA
end

local function split(str, sep)
    local out = {}
    if not str or str == "" then return out end
    for part in (str .. sep):gmatch("(.-)" .. sep:gsub("%p", "%%%0")) do out[#out + 1] = part end
    return out
end

--[[
  Renvoie { id, fen, sec, mate, n, line = { uci… }, alts = { [ply] = { {move, reply, mates} } }, text }
  n = nombre de coups du joueur dans la solution.
]]
function Problems.get(id)
    local r = data()[id]
    if not r then return nil end
    local p = { id = id, fen = r[1], sec = r[2], mate = r[3] == 1, line = {}, alts = {}, text = r[6] }
    for u in r[4]:gmatch("%S+") do p.line[#p.line + 1] = u end
    p.n = math.floor((#p.line + 1) / 2)
    for _, group in ipairs(split(r[5], "|")) do
        local ply, list = group:match("^(%d+)=(.*)$")
        if ply then
            local alts = {}
            for _, item in ipairs(split(list, ",")) do
                local parts = split(item, ">")
                alts[#alts + 1] = { move = parts[1], reply = parts[2], mates = parts[3] and split(parts[3], ";") or nil }
            end
            p.alts[tonumber(ply)] = alts
        end
    end
    return p
end

-- « Les blancs jouent et font mat en 2 coups »
function Problems.goal(p)
    local side = Chess.new(p.fen).turn == "w" and "Les Blancs" or "Les Noirs"
    if p.mate then
        return side .. " jouent et font mat en " .. p.n .. (p.n > 1 and " coups" or " coup")
    end
    return side .. " " .. (GOALS[p.sec] or "jouent et gagnent")
end

function Problems.chapterOf(id)
    for _, c in ipairs(Problems.CHAPTERS) do
        if id >= c.first and id <= c.last then return c end
    end
    return Problems.CHAPTERS[1]
end

---------------------------------------------------------------------------
-- Progression
---------------------------------------------------------------------------

-- Prépare data.problems ; importe la progression de l'ancienne appli « Polgar » si elle existe
function Problems.ensure(d, old)
    if not d.problems then
        d.problems = { solved = {}, first_try = {}, failed = {}, revealed = {}, current = 1,
            streak = 0, best_streak = 0, attempts = 0 }
    end
    local P = d.problems
    P.solved = P.solved or {}
    P.first_try = P.first_try or {}
    P.failed = P.failed or {}
    P.revealed = P.revealed or {}
    P.current = P.current or 1
    if old and not P.imported then
        local n = 0
        for k, v in pairs(old.solved or {}) do
            local id = tonumber(k)
            if v and id and id >= 1 and id <= Problems.TOTAL then
                P.solved[id] = true
                n = n + 1
            end
        end
        if tonumber(old.current) then P.current = math.max(1, math.min(Problems.TOTAL, tonumber(old.current))) end
        P.imported = true
        P.imported_count = n
    end
    return P
end

function Problems.solvedCount(P, c)
    local n = 0
    local first, last = c and c.first or 1, c and c.last or Problems.TOTAL
    for id in pairs(P.solved) do
        if id >= first and id <= last then n = n + 1 end
    end
    return n
end

-- Prochain problème non résolu à partir de `from` (dans le chapitre si donné)
function Problems.nextUnsolved(P, from, c)
    local first, last = c and c.first or 1, c and c.last or Problems.TOTAL
    from = math.max(first, math.min(last, from or first))
    for id = from, last do
        if not P.solved[id] then return id end
    end
    for id = first, from - 1 do
        if not P.solved[id] then return id end
    end
    return nil
end

---------------------------------------------------------------------------
-- Une séance de résolution
---------------------------------------------------------------------------

local Puzzle = {}
Puzzle.__index = Puzzle
Problems.Puzzle = Puzzle

--[[
  opts = { id, engine (peut être nil), schedule(sec, fn), onUpdate(ev) }
  États : "jeu" (à vous), "attente" (réponse / vérification), "resolu", "rate"
]]
function Puzzle.new(opts)
    local self = setmetatable({}, Puzzle)
    self.prob = Problems.get(opts.id)
    self.id = opts.id
    self.engine = opts.engine
    self.schedule = opts.schedule
    self.onUpdate = opts.onUpdate or function() end
    self.mistakes = 0
    self.gen = 0
    self:reset()
    return self
end

function Puzzle:reset()
    self.pos = Chess.new(self.prob.fen)
    self.side = self.pos.turn
    self.played = {}       -- coups joués (uci), les deux camps
    self.k = 1             -- prochain coup de la solution du livre
    self.on_line = true    -- on suit encore la solution du livre
    self.override = nil    -- coups finals acceptés après une variante du livre
    self.state = "jeu"
    self.last = nil
    self.message = nil
    self.snap = nil
    self.gen = self.gen + 1
    self.hint_stage = 0
end

-- coups encore à jouer par le joueur (celui-ci compris)
function Puzzle:movesLeft()
    return self.prob.n - math.floor((#self.played + 1) / 2)
end

function Puzzle:_push(m)
    self.pos = self.pos:makeMove(m)
    self.played[#self.played + 1] = Chess.moveToUci(m)
    self.last = { from = m.from, to = m.to }
end

function Puzzle:_snapshot()
    local pl = {}
    for i, u in ipairs(self.played) do pl[i] = u end
    self.snap = { pos = self.pos, played = pl, k = self.k, on_line = self.on_line,
        override = self.override, last = self.last }
end

function Puzzle:isMate()
    return #self.pos:legalMoves() == 0 and self.pos:inCheck()
end

function Puzzle:_solved()
    self.state = "resolu"
    self.message = (self.prob.mate or self:isMate()) and "Échec et mat !" or "Bravo, c'est la solution !"
    if self.mistakes == 0 then self.message = self.message .. " Résolu du premier coup." end
    self.onUpdate("resolu")
end

function Puzzle:_wrong(text)
    self.mistakes = self.mistakes + 1
    self.state = "rate"
    self.message = text
    self.onUpdate("rate")
end

-- La défense : coup donné (livre) ou meilleure défense de Stockfish
function Puzzle:_reply(uci)
    local gen = self.gen
    self.state = "attente"
    self.onUpdate("attente")
    local function play(u)
        if gen ~= self.gen then return end
        local m = u and self.pos:findUci(u)
        if not m then m = self.pos:legalMoves()[1] end
        if not m then
            if self:isMate() then return self:_solved() end
            return self:_wrong("Pat ! La partie est nulle : ce n'était pas la solution.")
        end
        self:_push(m)
        if self.on_line and not self.prob.mate and self.k > #self.prob.line then
            return self:_solved()
        end
        self.state = "jeu"
        self.message = "L'adversaire a répondu. À vous !"
        self.onUpdate("reponse")
    end
    if uci then
        if self.schedule then self.schedule(0.6, function() play(uci) end) else play(uci) end
        return
    end
    if not self.engine then return play(nil) end
    self.engine:analyse(self.pos:fen(), 1, 1200, function(lines, best)
        play((lines[1] and lines[1].move) or best)
    end)
end

local function contains(list, v)
    for _, x in ipairs(list or {}) do if x == v then return true end end
    return false
end

-- Le joueur joue un coup
function Puzzle:playerMove(m)
    if self.state ~= "jeu" or self.pos.turn ~= self.side then return end
    local p = self.prob
    local uci = Chess.moveToUci(m)
    local left = self:movesLeft()
    local ply = #self.played
    local book = self.on_line and p.line[self.k]
    self:_snapshot()
    self:_push(m)
    self.hint_stage = 0
    if self:isMate() then return self:_solved() end

    -- (trois problèmes du livre n'ont pas de solution enregistrée : Stockfish juge le coup)
    if #p.line == 0 then
        if not self.engine then return self:_solved() end
        local gen = self.gen
        self.state = "attente"
        self.message = "Je vérifie votre coup…"
        self.onUpdate("attente")
        self.engine:analyse(self.pos:fen(), 1, 1500, function(lines)
            if gen ~= self.gen then return end
            local l = lines[1]
            if l and (l.cp or 0) <= -300 then return self:_solved() end
            self:_wrong("Ce coup ne donne pas un avantage décisif. Touchez « Réessayer ».")
        end)
        return
    end

    -- après une variante du livre : seuls certains coups finissent
    if self.override then
        if contains(self.override, uci) then return self:_solved() end
        if not p.mate then return self:_wrong("Ce n'est pas le coup qui conclut. Touchez « Réessayer ».") end
    end

    if p.mate and left <= 1 then
        return self:_wrong("Ce coup ne fait pas mat. Touchez « Réessayer » pour reprendre la position.")
    end

    if book and uci == book then
        self.k = self.k + 1
        if self.k > #p.line then return self:_solved() end
        local reply = p.line[self.k]
        self.k = self.k + 1
        return self:_reply(reply)
    end

    -- variante prévue par le livre
    if self.on_line then
        for _, alt in ipairs(p.alts[ply] or {}) do
            if alt.move == uci then
                if not alt.reply then return self:_solved() end
                self.on_line = false
                self.override = alt.mates
                return self:_reply(alt.reply)
            end
        end
    end

    if not p.mate then
        return self:_wrong("Ce n'est pas le coup du livre. Cherchez encore ! Touchez « Réessayer ».")
    end
    -- autre coup : mate-t-il quand même à temps ? (on demande à Stockfish)
    if not self.engine then
        return self:_wrong("Ce n'est pas le coup attendu. Touchez « Réessayer ».")
    end
    local gen = self.gen
    self.state = "attente"
    self.message = "Je vérifie votre coup…"
    self.onUpdate("attente")
    self.engine:analyse(self.pos:fen(), 1, 1500, function(lines)
        if gen ~= self.gen then return end
        local l = lines[1]
        -- l'adversaire est au trait : un mat contre lui donne mate < 0
        if l and l.mate and l.mate < 0 and -l.mate <= left - 1 then
            self.on_line = false
            self.override = nil
            return self:_reply(nil)
        end
        self:_wrong("Ce coup ne mate pas en " .. left .. (left > 1 and " coups" or " coup")
            .. " : l'adversaire a une défense. Touchez « Réessayer ».")
    end)
end

-- Revenir juste avant le dernier coup du joueur (après une erreur)
function Puzzle:retry()
    local sn = self.snap
    self.gen = self.gen + 1
    if not sn then
        local mistakes = self.mistakes
        self:reset()
        self.mistakes = mistakes
    else
        self.pos, self.played, self.k, self.on_line = sn.pos, sn.played, sn.k, sn.on_line
        self.override, self.last = sn.override, sn.last
        self.state = "jeu"
    end
    self.message = nil
    self.onUpdate("reessai")
end

-- Coup conseillé maintenant (livre si on le suit). cb(uci)
function Puzzle:suggestion(cb)
    if self.state == "rate" then self:retry() end
    if self.state ~= "jeu" then return cb(nil) end
    if self.on_line then return cb(self.prob.line[self.k]) end
    if self.override and self.override[1] then return cb(self.override[1]) end
    if not self.engine then return cb(nil) end
    local gen = self.gen
    self.engine:analyse(self.pos:fen(), 1, 1500, function(lines, best)
        if gen ~= self.gen then return end
        cb((lines[1] and lines[1].move) or best)
    end)
end

-- Solution du livre en notation française : « 1. Dg7# » …
function Problems.solutionText(prob)
    local pos = Chess.new(prob.fen)
    local parts = {}
    local num = pos.fullmove
    for i, u in ipairs(prob.line) do
        local m = pos:findUci(u)
        if not m then break end
        local san = pos:san(m)
        if pos.turn == "w" then
            parts[#parts + 1] = num .. ". " .. san
        else
            parts[#parts + 1] = (i == 1 and (num .. "… ") or "") .. san
            num = num + 1
        end
        pos = pos:makeMove(m)
    end
    return table.concat(parts, " ")
end

---------------------------------------------------------------------------
-- Écrans
---------------------------------------------------------------------------

function Problems.screens()
    local SpinWidget = require("ui/widget/spinwidget")
    local InfoMessage = require("ui/widget/infomessage")
    local ButtonDialog = require("ui/widget/buttondialog")
    local UIManager = require("ui/uimanager")
    local Board = require("cc_board")
    local Draw = require("cc_draw")
    local UI = require("cc_ui")
    local s = UI.s

    local Screens = {}

    -------------------------------------------------------------------
    -- Accueil des problèmes
    -------------------------------------------------------------------
    local Hub = UI.Canvas:extend{ app = nil }
    Screens.Hub = Hub

    function Hub:draw(bb)
        local app = self.app
        local P = app:problemsData()
        local W = self.W
        local m = s(18)
        local y = self:header(bb, "Problèmes d'échecs", "Menu", function() self:close() end)
        y = y + s(10)
        UI.text(bb, UI.face(14), "« Chess: 5334 problèmes, combinaisons et parties » de László Polgár", m, y, UI.DIM)
        y = y + UI.lineHeight(UI.face(14)) + s(2)
        local total = Problems.solvedCount(P)
        local tw = UI.text(bb, UI.face(30, true), tostring(total), m, y)
        UI.text(bb, UI.face(15), "/ " .. Problems.TOTAL .. " résolus", m + tw + s(10), y + s(10), UI.DIM)
        local ft = 0
        for _ in pairs(P.first_try) do ft = ft + 1 end
        UI.textRight(bb, UI.face(13), "série " .. (P.streak or 0) .. " · record " .. (P.best_streak or 0)
            .. " · du 1er coup " .. ft, W - m, y + s(12), UI.GRAY)
        y = y + UI.lineHeight(UI.face(30, true)) + s(4)

        -- mes erreurs (exercices tirés de vos parties)
        local Mistakes = require("cc_mistakes")
        local todo = Mistakes.counts(app.data)
        local mw = W - 2 * m
        bb:paintBorder(m, y, mw, s(52), s(1), UI.BLACK, s(12))
        UI.text(bb, UI.face(16, true), "Mes erreurs à retravailler", m + s(14), y + s(6))
        UI.text(bb, UI.face(13), todo > 0 and (todo .. " position" .. (todo > 1 and "s" or "") .. " tirée" .. (todo > 1 and "s" or "") .. " de vos parties")
            or "Exercices tirés des erreurs de vos parties", m + s(14), y + s(30), UI.DIM)
        UI.textRight(bb, UI.face(22), "›", m + mw - s(14), y + s(10), UI.GRAY)
        self:region(m, y, mw, s(52), function() app:openMistakes() end)
        y = y + s(62)

        -- reprendre
        local cur = P.current or 1
        local bw = W - 2 * m
        local rh = s(60)
        Draw.roundedRect(bb, m, y, bw, rh, s(12), nil, 0xEE)
        UI.text(bb, UI.face(17, true), "Reprendre : problème n° " .. cur, m + s(14), y + s(7))
        local cc = Problems.chapterOf(cur)
        UI.text(bb, UI.face(13), cc.name .. (P.solved[cur] and " · déjà résolu" or ""), m + s(14), y + s(33), UI.DIM)
        UI.textRight(bb, UI.face(22), "›", m + bw - s(14), y + s(14), UI.GRAY)
        self:region(m, y, bw, rh, function() app:openPuzzle(cur) end)
        y = y + rh + s(12)

        -- les chapitres du livre
        local avail = self.H - y - s(96)
        local row = math.min(s(66), math.floor(avail / #Problems.CHAPTERS))
        local fn, fs = UI.face(16, true), UI.face(12)
        for i, c in ipairs(Problems.CHAPTERS) do
            local ry = y + (i - 1) * row
            local n = Problems.solvedCount(P, c)
            local cnt = c.last - c.first + 1
            UI.text(bb, fn, c.name, m, ry + s(4))
            UI.textRight(bb, UI.face(14), n .. " / " .. cnt .. "  ›", W - m, ry + s(6), n >= cnt and UI.GRAY or UI.BLACK)
            local by = ry + s(4) + UI.lineHeight(fn) + s(2)
            local bh = s(10)
            local barw = math.floor(bw * 0.55)
            bb:paintBorder(m, by, barw, bh, 1, UI.GRAY, s(5))
            local fw = math.floor((barw - 4) * n / cnt)
            if fw > 0 then Draw.roundedRect(bb, m + 2, by + 2, math.max(fw, s(4)), bh - 4, s(3), UI.GREEN, 0x55) end
            UI.text(bb, fs, "n° " .. c.first .. (c.last > c.first and (" à " .. c.last) or ""), m + barw + s(10), by - s(4), UI.GRAY)
            if i < #Problems.CHAPTERS then bb:paintRect(m, ry + row - 1, bw, 1, UI.LIGHT) end
            self:region(m, ry, bw, row, function()
                local start = (cur >= c.first and cur <= c.last) and cur or c.first
                app:openPuzzle(Problems.nextUnsolved(P, start, c) or c.first)
            end, function()
                app:openPuzzle(c.first)
            end)
        end
        y = y + row * #Problems.CHAPTERS + s(10)

        local lbl = "Aller au problème n°…"
        local pw = UI.textWidth(UI.face(15), lbl) + s(40)
        UI.pill(bb, (W - pw) / 2, y, pw, s(38), lbl, UI.face(15))
        self:region((W - pw) / 2, y, pw, s(38), function()
            UIManager:show(SpinWidget:new{
                title_text = "Numéro du problème", value = cur, value_min = 1, value_max = Problems.TOTAL,
                value_step = 1, value_hold_step = 50, ok_text = "Ouvrir", cancel_text = "Annuler",
                callback = function(spin) app:openPuzzle(spin.value) end,
            })
        end)
        y = y + s(42)
        local note
        if P.imported_count and P.imported_count > 0 and not P.import_seen then
            note = "Votre progression de l'ancienne appli Polgár est reprise : " .. P.imported_count .. " problèmes résolus."
        else
            note = "Touchez un chapitre pour le premier problème non résolu ; appui long : depuis le début."
        end
        UI.textCentered(bb, UI.face(12), UI.ellipsize(UI.face(12), note, W - 2 * m), W / 2, y, UI.GRAY)
    end

    function Hub:onClose()
        local P = self.app:problemsData()
        if P.imported_count then P.import_seen = true; self.app:save() end
    end

    -------------------------------------------------------------------
    -- Résolution d'un problème
    -------------------------------------------------------------------
    local PuzzleScreen = UI.Canvas:extend{ app = nil, id = 1 }
    Screens.PuzzleScreen = PuzzleScreen

    function PuzzleScreen:setup()
        self.mg = s(6)
        self.tool_h = s(46)
        local head = s(40) + s(30)
        local panel = s(150)
        local bs = math.min(self.W - 2 * self.mg, self.H - head - self.tool_h - panel)
        self.board = Board:new{ size = bs }
        self:load(self.id)
    end

    function PuzzleScreen:load(id)
        id = math.max(1, math.min(Problems.TOTAL, id))
        self.id = id
        local app = self.app
        local P = app:problemsData()
        P.current = id
        app:save()
        self.selected, self.targets, self.arrow, self.mark = nil, nil, nil, nil
        self.show_solution = false
        self.used_hint = false
        self.page = 1
        self.puzzle = Puzzle.new{
            id = id, engine = app.engine,
            schedule = app.schedule,
            onUpdate = function(ev) self:onPuzzle(ev) end,
        }
    end

    function PuzzleScreen:onClose()
        if self.puzzle then self.puzzle.gen = self.puzzle.gen + 1 end
        if self.app.engine then self.app.engine:cancelAll() end
    end

    function PuzzleScreen:onPuzzle(ev)
        if self.closed then return end
        local app = self.app
        local P = app:problemsData()
        local id = self.id
        if ev == "resolu" then
            local first = self.puzzle.mistakes == 0 and not P.revealed[id] and not self.used_hint
            if not P.solved[id] then
                P.solved[id] = true
                if first then P.first_try[id] = true end
            end
            if first then
                P.streak = (P.streak or 0) + 1
                if P.streak > (P.best_streak or 0) then P.best_streak = P.streak end
            end
            app:save()
        elseif ev == "rate" then
            P.failed[id] = (P.failed[id] or 0) + 1
            P.streak = 0
            app:save()
        end
        self.arrow, self.mark = nil, nil
        self.page = 1
        self:refresh("ui")
    end

    function PuzzleScreen:draw(bb)
        local app = self.app
        local P = app:problemsData()
        local pz = self.puzzle
        local prob = pz.prob
        local W, mg = self.W, self.mg
        local y = self:header(bb, "Problème n° " .. self.id, "Problèmes", function() self:close() end)
        -- ligne d'info
        local info = Problems.goal(prob)
        local fb = UI.face(16, true)
        UI.textCentered(bb, fb, UI.ellipsize(fb, info, W - s(110)), W / 2, y + s(2))
        if P.solved[self.id] then
            UI.textRight(bb, UI.face(13), "✓ résolu", W - mg * 3, y + s(5), UI.DIM)
        end
        y = y + s(28)

        local b = self.board
        b.pos = pz.pos
        b.flipped = pz.side == "b"
        b.last_move = pz.last
        b.selected, b.targets = self.selected, self.targets
        b.arrows = {}
        b.marks = {}
        if self.arrow then b.arrows[1] = self.arrow end
        if self.mark then b.marks[1] = self.mark end
        b.badges = {}
        local bx = math.floor((W - b.size) / 2)
        b:paintTo(bb, bx, y)
        self:region(bx, y, b.size, b.size, function(ges)
            local sq = b:squareAt(ges.pos.x, ges.pos.y)
            if sq then self:onSquare(sq) end
        end)
        y = y + b.size + s(4)

        -- barre d'outils
        local items
        if pz.state == "resolu" then
            items = {
                { "‹ Préc.", function() self:go(-1) end },
                { "Rejouer", function() self:load(self.id); self:refresh("ui") end },
                { "Suivant ›", function() self:goNext() end, true },
            }
        elseif pz.state == "rate" then
            items = {
                { "‹ Préc.", function() self:go(-1) end },
                { "Réessayer", function() pz:retry() end, true },
                { "Solution", function() self:showSolution() end },
                { "Suiv. ›", function() self:go(1) end },
            }
        else
            items = {
                { "‹ Préc.", function() self:go(-1) end },
                { "Indice", function() self:hint() end },
                { "Solution", function() self:showSolution() end },
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

        -- texte (le commentaire du livre s'affiche une fois le problème résolu ou la solution demandée)
        local px = mg * 3
        local pw = W - 2 * px
        local text
        if pz.state == "attente" then
            text = pz.message and pz.message:find("vérifie") and pz.message or "L'adversaire réfléchit…"
        elseif pz.message then
            text = pz.message
        else
            local c = Problems.chapterOf(self.id)
            text = c.name .. " · " .. (self.id - c.first + 1) .. " sur " .. (c.last - c.first + 1)
                .. ". Touchez une pièce puis sa case d'arrivée."
        end
        if pz.state == "resolu" then
            text = text .. "\nRésolus : " .. Problems.solvedCount(P) .. " / " .. Problems.TOTAL .. " · série : " .. (P.streak or 0)
        end
        if self.show_solution or pz.state == "resolu" then
            local sol = prob.text ~= "" and prob.text or Problems.solutionText(prob)
            text = text .. "\n\n" .. (self.show_solution and pz.state ~= "resolu" and "Solution : " or "") .. sol
        end
        local ft = UI.face(15)
        local lh = UI.lineHeight(ft)
        local lines = UI.wrap(ft, text, pw)
        local top = y
        local fit = math.max(1, math.floor((self.H - y - s(4)) / lh))
        if #lines > fit then fit = math.max(1, fit - 1) end
        local pages = math.max(1, math.ceil(#lines / fit))
        if (self.page or 1) > pages then self.page = 1 end
        local first = ((self.page or 1) - 1) * fit + 1
        for i = first, math.min(#lines, first + fit - 1) do
            UI.text(bb, ft, lines[i], px, y)
            y = y + lh
        end
        if pages > 1 then
            UI.textRight(bb, UI.face(13), "suite " .. self.page .. "/" .. pages .. " ▸", W - px,
                self.H - UI.lineHeight(UI.face(13)) - s(2), UI.GRAY)
            self:region(0, top, W, self.H - top, function()
                self.page = self.page % pages + 1
                self:refresh("ui")
            end)
        end
    end

    function PuzzleScreen:go(dir)
        self:load(self.id + dir)
        self:refresh("ui")
    end

    function PuzzleScreen:goNext()
        local P = self.app:problemsData()
        local nxt = Problems.nextUnsolved(P, self.id + 1) or (self.id + 1)
        self:load(nxt)
        self:refresh("ui")
    end

    function PuzzleScreen:onPrevKey() self:go(-1) end
    function PuzzleScreen:onNextKey()
        if self.puzzle.state == "resolu" then self:goNext() else self:go(1) end
    end
    function PuzzleScreen:onSwipe(dir)
        if dir == "east" then self:go(-1) elseif dir == "west" then self:onNextKey() end
    end

    function PuzzleScreen:hint()
        local pz = self.puzzle
        self.used_hint = true
        pz:suggestion(function(uci)
            if self.closed or not uci then return end
            local m = pz.pos:findUci(uci)
            if not m then return end
            pz.hint_stage = (pz.hint_stage or 0) + 1
            if pz.hint_stage == 1 then
                self.mark = { sq = m.from, rgb = UI.GOLD, gray = 0xC8 }
                self.arrow = nil
                pz.message = "Indice : la pièce à jouer est marquée. Touchez encore « Indice » pour voir le coup."
            else
                self.mark = nil
                self.arrow = { from = m.from, to = m.to, rgb = { 120, 190, 120 }, gray = 0x60 }
                pz.message = "Le coup à jouer : " .. pz.pos:san(m) .. "."
            end
            self:refresh("ui")
        end)
    end

    function PuzzleScreen:showSolution()
        local P = self.app:problemsData()
        if not P.solved[self.id] then P.revealed[self.id] = true end
        P.streak = 0
        self.app:save()
        self.show_solution = true
        if self.puzzle.state == "rate" then self.puzzle:retry() end
        self:refresh("ui")
    end

    function PuzzleScreen:onSquare(sq)
        local pz = self.puzzle
        if pz.state ~= "jeu" or pz.pos.turn ~= pz.side then return end
        local pos = pz.pos
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
                                pz.message = nil
                                pz:playerMove(mv)
                                self:refresh("ui")
                            end }
                        end
                    end
                end
                dialog = ButtonDialog:new{ title = "Promotion du pion", buttons = { row } }
                UIManager:show(dialog)
            elseif #cands == 1 then
                pz.message = nil
                pz:playerMove(cands[1])
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

return Problems
