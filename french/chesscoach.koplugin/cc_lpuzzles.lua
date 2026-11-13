-- Problèmes Lichess par thème et par difficulté
-- Les problèmes viennent de lichess.org ; chaque résultat est renvoyé à Lichess
-- et compte pour votre classement « problèmes » (comme sur le site).

local Chess = require("cc_chess")
local Lichess = require("cc_lichess")

local LP = {}

LP.BATCH = 15          -- problèmes demandés à la fois
LP.REFILL = 3          -- on redemande quand il en reste si peu

---------------------------------------------------------------------------
-- Thèmes (clés Lichess → noms français)
---------------------------------------------------------------------------

LP.GROUPS = {
    { name = "Mélange et mats", items = {
        { "mix", "Mélange" }, { "mateIn1", "Mat en 1" }, { "mateIn2", "Mat en 2" }, { "mateIn3", "Mat en 3" },
        { "mateIn4", "Mat en 4" }, { "backRankMate", "Mat du couloir" }, { "smotheredMate", "Mat étouffé" },
        { "mate", "Tous les mats" },
    } },
    { name = "Tactiques", items = {
        { "fork", "Fourchette" }, { "pin", "Clouage" }, { "skewer", "Enfilade" },
        { "discoveredAttack", "Attaque à la découverte" }, { "doubleCheck", "Échec double" },
        { "hangingPiece", "Pièce en prise" }, { "trappedPiece", "Pièce piégée" },
        { "sacrifice", "Sacrifice" }, { "deflection", "Déviation" }, { "attraction", "Attraction" },
        { "clearance", "Dégagement" }, { "intermezzo", "Coup intermédiaire" },
        { "capturingDefender", "Éliminer le défenseur" }, { "kingsideAttack", "Attaque du roi" },
        { "quietMove", "Coup tranquille" }, { "defensiveMove", "Coup défensif" }, { "zugzwang", "Zugzwang" },
    } },
    { name = "Pions", items = {
        { "advancedPawn", "Pion avancé" }, { "promotion", "Promotion" }, { "enPassant", "Prise en passant" },
    } },
    { name = "Phase de jeu", items = {
        { "opening", "Ouverture" }, { "middlegame", "Milieu de partie" }, { "endgame", "Finale" },
        { "rookEndgame", "Finale de tours" }, { "pawnEndgame", "Finale de pions" },
        { "queenEndgame", "Finale de dames" },
    } },
    { name = "Longueur et but", items = {
        { "oneMove", "Un seul coup" }, { "short", "Court" }, { "long", "Long" }, { "veryLong", "Très long" },
        { "crushing", "Gagner nettement" }, { "advantage", "Prendre l'avantage" }, { "equality", "Sauver la partie" },
    } },
}

LP.NAMES = {}
for _, g in ipairs(LP.GROUPS) do
    for _, it in ipairs(g.items) do LP.NAMES[it[1]] = it[2] end
end
-- autres thèmes que Lichess peut renvoyer sur un problème
for k, v in pairs({ interference = "Interception", xRayAttack = "Rayon X", exposedKing = "Roi exposé",
    underPromotion = "Sous-promotion", bishopEndgame = "Finale de fous", knightEndgame = "Finale de cavaliers",
    master = "Parties de maîtres", mateIn5 = "Mat en 5", anastasiaMate = "Mat d'Anastasia",
    arabianMate = "Mat arabe", hookMate = "Mat de l'hameçon", bodenMate = "Mat de Boden",
    doubleBishopMate = "Mat des deux fous", dovetailMate = "Mat de la queue d'aronde",
    queensideAttack = "Attaque à l'aile dame", castling = "Roque", queenRookEndgame = "Finale dame et tour",
    masterVsMaster = "Maîtres contre maîtres", superGM = "Super grands maîtres", playerGames = "Vos parties" }) do
    LP.NAMES[k] = LP.NAMES[k] or v
end

function LP.themeName(k) return LP.NAMES[k] or k end

LP.DIFFICULTIES = {
    { "easiest", "Très facile" }, { "easier", "Facile" }, { "normal", "Normal" },
    { "harder", "Difficile" }, { "hardest", "Très difficile" },
}
function LP.difficultyName(k)
    for _, d in ipairs(LP.DIFFICULTIES) do if d[1] == k then return d[2] end end
    return k
end

---------------------------------------------------------------------------
-- Données gardées dans la sauvegarde
---------------------------------------------------------------------------

function LP.ensure(data)
    local d = data.lpuzzles
    if type(d) ~= "table" then d = {}; data.lpuzzles = d end
    d.angle = d.angle or "mix"
    d.difficulty = d.difficulty or "normal"
    d.batch = d.batch or {}
    d.idx = d.idx or 1
    d.queue = d.queue or {}       -- résultats pas encore envoyés à Lichess
    d.won = d.won or 0
    d.lost = d.lost or 0
    d.streak = d.streak or 0
    return d
end

function LP.remaining(d)
    return math.max(0, #d.batch - d.idx + 1)
end

---------------------------------------------------------------------------
-- Lecture de la partie (notation anglaise de Lichess : K Q R B N)
---------------------------------------------------------------------------

function LP.parseSan(pos, tok)
    tok = tok:gsub("[%+#!?]", "")
    if tok == "" then return nil end
    local legal = pos:legalMoves()
    if tok == "O-O" or tok == "0-0" or tok == "O-O-O" or tok == "0-0-0" then
        local want = (#tok == 3) and "K" or "Q"
        for _, m in ipairs(legal) do if m.castle == want then return m end end
        return nil
    end
    local promo
    local base, pr = tok:match("^(.-)=?([QRBNqrbn])$")
    if base and base:match("[a-h][1-8]$") and not tok:match("^[QRBNK]") then
        tok, promo = base, pr:lower()
    end
    local piece, rest = tok:match("^([KQRBN])(.*)$")
    piece = piece or "P"
    rest = rest or tok
    rest = rest:gsub("x", "")
    local dis, to = rest:match("^(.-)([a-h][1-8])$")
    if not to then return nil end
    local found
    for _, m in ipairs(legal) do
        if m.piece:upper() == piece and Chess.sqName(m.to) == to and m.promo == promo then
            local from = Chess.sqName(m.from)
            local okd = true
            for c in dis:gmatch(".") do
                if not from:find(c, 1, true) then okd = false end
            end
            if okd then
                if found then return nil end     -- ambigu
                found = m
            end
        end
    end
    return found
end

local CASTLE_FIX = { e1h1 = "e1g1", e1a1 = "e1c1", e8h8 = "e8g8", e8a8 = "e8c8" }

-- Transforme un problème reçu de Lichess en ce dont l'appli a besoin
function LP.compact(raw, angle)
    local g, p = raw.game, raw.puzzle
    if type(g) ~= "table" or type(p) ~= "table" or type(g.pgn) ~= "string" or type(p.solution) ~= "table" then return nil end
    local pos = Chess.new()
    local last
    for tok in g.pgn:gmatch("%S+") do
        if not tok:match("^%d+%.") and not tok:match("^[%d/%-]+$") then
            local m = LP.parseSan(pos, tok)
            if not m then return nil end
            last = Chess.moveToUci(m)
            pos = pos:makeMove(m)
        end
    end
    local fen = pos:fen()
    -- on vérifie que la solution est jouable
    local sol = {}
    local q = pos
    for i, u in ipairs(p.solution) do
        u = CASTLE_FIX[u] and q:findUci(CASTLE_FIX[u]) and not q:findUci(u) and CASTLE_FIX[u] or u
        local m = q:findUci(u)
        if not m then return nil end
        sol[i] = u
        q = q:makeMove(m)
    end
    local players = {}
    for _, pl in ipairs(type(g.players) == "table" and g.players or {}) do
        if type(pl) == "table" and pl.color then
            players[pl.color] = (pl.name or "?") .. (pl.rating and (" (" .. pl.rating .. ")") or "")
        end
    end
    local themes = {}
    for _, t in ipairs(type(p.themes) == "table" and p.themes or {}) do themes[#themes + 1] = t end
    return {
        id = p.id, rating = p.rating, plays = p.plays, themes = themes,
        fen = fen, last = last, solution = sol, angle = angle,
        white = players.white, black = players.black, clock = g.clock,
    }
end

---------------------------------------------------------------------------
-- Échanges avec Lichess
---------------------------------------------------------------------------

local Net = {}
Net.__index = Net
LP.Net = Net

function Net.new(token)
    return setmetatable({ token = token, keep = Lichess.Keep.new(token), anon = nil }, Net)
end

function Net:close()
    if self.keep then self.keep:close() end
    if self.anon then self.anon:close() end
end

local function errText(code, body)
    local j = Lichess.decode(body or "")
    local e = j and j.error
    if code == 401 then return "Lichess refuse la clé (elle a peut-être été supprimée)." end
    if code == 429 then return "Lichess demande de patienter une minute (trop de requêtes)." end
    if code then return "Lichess a répondu : " .. tostring(e or code) end
    return "Pas de connexion à Lichess (" .. tostring(body) .. ")."
end

local function absorb(d, j, angle, anon)
    if type(j) ~= "table" then return 0 end
    if not anon and type(j.glicko) == "table" and tonumber(j.glicko.rating) then
        d.rating = math.floor(j.glicko.rating + 0.5)
        d.provisional = j.glicko.provisional == true
    end
    local n = 0
    if type(j.puzzles) == "table" then
        local have = {}
        for i = d.idx, #d.batch do have[d.batch[i].id] = true end
        for _, raw in ipairs(j.puzzles) do
            local c = LP.compact(raw, angle)
            if c and not have[c.id] then
                d.batch[#d.batch + 1] = c
                have[c.id] = true
                n = n + 1
            end
        end
    end
    return n
end

-- Va chercher des problèmes ; renvoie le nombre reçu, ou nil et un message
function Net:fetch(d)
    -- on oublie les problèmes déjà faits
    if d.idx > 1 then
        local keep = {}
        for i = d.idx, #d.batch do keep[#keep + 1] = d.batch[i] end
        d.batch, d.idx = keep, 1
    end
    local path = "/api/puzzle/batch/" .. d.angle .. "?nb=" .. LP.BATCH .. "&difficulty=" .. d.difficulty
    local code, body
    if self.token and not self.no_scope then
        code, body = self.keep:send("GET", path)
        if code == 403 then
            self.no_scope = true
        elseif code == 401 then
            return nil, errText(code, body)
        end
    end
    local anon = false
    if not code or code == 403 then
        anon = true
        -- sans la permission « problèmes », on joue sans compte (rien n'est enregistré sur Lichess)
        self.anon = self.anon or Lichess.Keep.new(nil)
        code, body = self.anon:send("GET", path)
    end
    if code ~= 200 then return nil, errText(code, body) end
    local j = Lichess.decode(body)
    if type(j) ~= "table" then return nil, "Réponse illisible de Lichess." end
    local n = absorb(d, j, d.angle, anon)
    if n == 0 and LP.remaining(d) == 0 then
        return nil, "Lichess n'a plus de nouveaux problèmes pour ce choix. Essayez un autre thème ou une autre difficulté."
    end
    return n
end

-- Envoie les résultats en attente ; renvoie true, ou nil et un message
function Net:flush(d, diffs)
    if not self.token or self.no_scope or #d.queue == 0 then return true end
    -- regroupés par thème (Lichess le demande dans l'adresse)
    local byAngle, order = {}, {}
    for _, r in ipairs(d.queue) do
        local a = r.angle or "mix"
        if not byAngle[a] then byAngle[a] = {}; order[#order + 1] = a end
        table.insert(byAngle[a], r)
    end
    local left = {}
    local lastErr
    for _, a in ipairs(order) do
        local parts = {}
        for _, r in ipairs(byAngle[a]) do
            parts[#parts + 1] = '{"id":"' .. tostring(r.id):gsub('[^%w]', '') .. '","win":' .. (r.win and "true" or "false") .. ',"rated":true}'
        end
        local body = '{"solutions":[' .. table.concat(parts, ",") .. ']}'
        local nb = 0
        if a == d.angle and LP.remaining(d) <= LP.REFILL then nb = LP.BATCH end
        local code, resp = self.keep:send("POST", "/api/puzzle/batch/" .. a .. "?nb=" .. nb
            .. (nb > 0 and ("&difficulty=" .. d.difficulty) or ""), body, "application/json")
        if code == 200 then
            local j = Lichess.decode(resp)
            if type(j) == "table" then
                if type(j.rounds) == "table" and diffs then
                    for _, rd in ipairs(j.rounds) do
                        if type(rd) == "table" and rd.id then diffs[rd.id] = tonumber(rd.ratingDiff) or 0 end
                    end
                end
                if nb > 0 and d.idx > 1 then
                    local keep = {}
                    for i = d.idx, #d.batch do keep[#keep + 1] = d.batch[i] end
                    d.batch, d.idx = keep, 1
                end
                absorb(d, j, a)
            end
        elseif code == 403 then
            self.no_scope = true
            return nil, "La clé Lichess n'a pas la permission « problèmes » : vos résultats ne sont pas enregistrés sur Lichess."
        else
            for _, r in ipairs(byAngle[a]) do left[#left + 1] = r end
            lastErr = errText(code, resp)
        end
    end
    d.queue = left
    if lastErr then return nil, lastErr end
    return true
end

---------------------------------------------------------------------------
-- Un problème en cours de résolution
---------------------------------------------------------------------------

local Run = {}
Run.__index = Run
LP.Run = Run

function Run.new(p, schedule, onUpdate)
    local self = setmetatable({ p = p, schedule = schedule, onUpdate = onUpdate, gen = 0 }, Run)
    self.start = Chess.new(p.fen)
    self.side = self.start.turn
    self.result = nil     -- true / false une fois décidé (le premier essai compte)
    self:reset()
    return self
end

function Run:reset()
    self.gen = self.gen + 1
    self.pos = self.start
    self.k = 1
    self.history = {}
    self.state = "jeu"
    self.message = nil
    self.wrong = nil
    if self.p.last then
        local a, b = Chess.sqFromName(self.p.last:sub(1, 2)), Chess.sqFromName(self.p.last:sub(3, 4))
        self.last = { from = a, to = b }
    else
        self.last = nil
    end
end

function Run:decide(win)
    if self.result == nil then self.result = win end
end

function Run:_play(uci)
    local m = self.pos:findUci(uci)
    self.history[#self.history + 1] = { pos = self.pos, last = self.last, k = self.k }
    self.pos = self.pos:makeMove(m)
    self.last = { from = m.from, to = m.to }
    self.k = self.k + 1
    return m
end

function Run:_finish()
    self.state = "resolu"
    self:decide(true)
    if self.onUpdate then self.onUpdate("resolu") end
end

function Run:playerMove(m)
    if self.state ~= "jeu" or self.pos.turn ~= self.side then return end
    local uci = Chess.moveToUci(m)
    local want = self.p.solution[self.k]
    local after = self.pos:makeMove(m)
    local mates = #after:legalMoves() == 0 and after:inCheck()
    if uci == want or mates then
        self.history[#self.history + 1] = { pos = self.pos, last = self.last, k = self.k }
        self.pos = after
        self.last = { from = m.from, to = m.to }
        self.k = self.k + 1
        if mates or self.k > #self.p.solution then
            self.message = "Bravo, c'est la bonne solution !"
            self:_finish()
            return
        end
        self.message = "Bon coup ! Continuez…"
        self.state = "attente"
        local gen = self.gen
        local reply = self.p.solution[self.k]
        self.schedule(0.5, function()
            if gen ~= self.gen then return end
            self:_play(reply)
            self.state = "jeu"
            if self.k > #self.p.solution then self:_finish() return end
            if self.onUpdate then self.onUpdate("coup") end
        end)
        if self.onUpdate then self.onUpdate("bon") end
        return
    end
    -- mauvais coup : on le montre, le problème compte comme raté
    self.wrong = { pos = self.pos, last = self.last }
    self.history[#self.history + 1] = { pos = self.pos, last = self.last, k = self.k }
    self.pos = after
    self.last = { from = m.from, to = m.to }
    self.state = "rate"
    self.message = "Ce n'est pas le bon coup (" .. self.wrong.pos:san(m) .. ")."
    self:decide(false)
    if self.onUpdate then self.onUpdate("rate") end
end

-- Revenir avant le mauvais coup pour chercher encore
function Run:retry()
    if self.state ~= "rate" or not self.wrong then return end
    self.gen = self.gen + 1
    local h = table.remove(self.history)
    self.pos, self.last = h.pos, h.last
    self.wrong = nil
    self.state = "jeu"
    self.message = "Cherchez encore… (le problème reste compté comme raté)"
    if self.onUpdate then self.onUpdate("retry") end
end

-- Le prochain coup de la solution (pour l'indice)
function Run:nextMove()
    if self.state ~= "jeu" then return nil end
    return self.pos:findUci(self.p.solution[self.k])
end

-- Joue toute la solution pour la montrer
function Run:showSolution()
    self.gen = self.gen + 1
    if self.state == "rate" then
        local h = table.remove(self.history)
        self.pos, self.last = h.pos, h.last
        self.wrong = nil
    end
    self:decide(false)
    local gen = self.gen
    self.state = "solution"
    self.message = "Voici la solution."
    local function step()
        if gen ~= self.gen then return end
        if self.k > #self.p.solution then
            self.state = "resolu"
            self.message = "Voici la solution. Le problème compte comme raté."
            if self.onUpdate then self.onUpdate("vu") end
            return
        end
        self:_play(self.p.solution[self.k])
        if self.onUpdate then self.onUpdate("coup") end
        self.schedule(0.9, step)
    end
    self.schedule(0.2, step)
end

-- La solution écrite (notation française de l'appli)
function LP.solutionText(p)
    local pos = Chess.new(p.fen)
    local out = {}
    for i, u in ipairs(p.solution) do
        local m = pos:findUci(u)
        if not m then break end
        local san = pos:san(m)
        if pos.turn == "w" then
            out[#out + 1] = pos.fullmove .. ". " .. san
        elseif i == 1 then
            out[#out + 1] = pos.fullmove .. "… " .. san
        else
            out[#out + 1] = san
        end
        pos = pos:makeMove(m)
    end
    return table.concat(out, " ")
end

---------------------------------------------------------------------------
-- Écrans
---------------------------------------------------------------------------

function LP.screens()
    local UIManager = require("ui/uimanager")
    local ButtonDialog = require("ui/widget/buttondialog")
    local Board = require("cc_board")
    local Draw = require("cc_draw")
    local UI = require("cc_ui")
    local s = UI.s
    local Screens = {}

    local function ratingLine(d, net)
        if net and (not net.token or net.no_scope) then
            return "Sans compte : vos résultats ne comptent pas sur Lichess"
        end
        if d.rating then
            return "Votre classement problèmes Lichess : " .. d.rating .. (d.provisional and " ?" or "")
        end
        return "Votre classement problèmes Lichess apparaîtra après le chargement"
    end

    -------------------------------------------------------------------
    -- Choix du thème et de la difficulté
    -------------------------------------------------------------------
    local Hub = UI.Canvas:extend{ app = nil }
    Screens.Hub = Hub

    function Hub:setup()
        local d = LP.ensure(self.app.data)
        self.angle, self.difficulty = d.angle, d.difficulty
    end

    function Hub:draw(bb)
        local app = self.app
        local d = LP.ensure(app.data)
        local W = self.W
        local m = s(18)
        local y = self:header(bb, "Problèmes Lichess", "Retour", function() self:close() end)
        y = y + s(8)
        UI.text(bb, UI.face(14), ratingLine(d, app._lpnet), m, y, UI.DIM)
        y = y + UI.lineHeight(UI.face(14))
        UI.text(bb, UI.face(13), "Réussis : " .. d.won .. " · ratés : " .. d.lost .. " · série : " .. d.streak
            .. (#d.queue > 0 and (" · " .. #d.queue .. " résultat(s) à envoyer") or ""), m, y, UI.GRAY)
        y = y + UI.lineHeight(UI.face(13)) + s(6)

        local f = UI.face(13)
        local fh = UI.face(13, true)
        local ph, gap = s(29), s(6)
        for _, g in ipairs(LP.GROUPS) do
            UI.text(bb, fh, g.name, m, y)
            y = y + UI.lineHeight(fh) + s(2)
            local x = m
            for _, it in ipairs(g.items) do
                local w = UI.textWidth(f, it[2]) + s(20)
                if x + w > W - m then x = m; y = y + ph + gap end
                UI.pill(bb, x, y, w, ph, it[2], f, it[1] == self.angle and { dark = true } or {})
                self:region(x, y, w, ph, function() self.angle = it[1]; self:refresh() end)
                x = x + w + gap
            end
            y = y + ph + s(7)
        end

        UI.text(bb, fh, "Difficulté (par rapport à votre classement)", m, y)
        y = y + UI.lineHeight(fh) + s(2)
        local x = m
        for _, it in ipairs(LP.DIFFICULTIES) do
            local w = UI.textWidth(f, it[2]) + s(24)
            if x + w > W - m then x = m; y = y + ph + gap end
            UI.pill(bb, x, y, w, ph, it[2], f, it[1] == self.difficulty and { dark = true } or {})
            self:region(x, y, w, ph, function() self.difficulty = it[1]; self:refresh() end)
            x = x + w + gap
        end
        y = y + ph + s(16)

        local same = self.angle == d.angle and self.difficulty == d.difficulty and LP.remaining(d) > 0
        local lbl = same and "Continuer" or "Commencer"
        local bw = s(300)
        local bx = math.floor((W - bw) / 2)
        UI.pill(bb, bx, y, bw, s(48), lbl .. " · " .. LP.themeName(self.angle), UI.face(17, true), { dark = true })
        self:region(bx, y, bw, s(48), function() self:start() end)
        y = y + s(56)
        UI.textCentered(bb, UI.face(12), UI.ellipsize(UI.face(12),
            "Un problème raté, l'indice ou la solution comptent comme un échec, comme sur Lichess.", W - 2 * m),
            W / 2, y, UI.GRAY)
    end

    function Hub:start()
        local app = self.app
        local d = LP.ensure(app.data)
        if self.angle ~= d.angle or self.difficulty ~= d.difficulty then
            d.angle, d.difficulty = self.angle, self.difficulty
            d.batch, d.idx = {}, 1
            app:save()
        end
        app:openLPuzzle(function() if not self.closed then self:refresh("ui") end end)
    end

    -------------------------------------------------------------------
    -- Résolution
    -------------------------------------------------------------------
    local Play = UI.Canvas:extend{ app = nil, onDone = nil }
    Screens.Play = Play

    function Play:setup()
        self.mg = s(6)
        self.tool_h = s(46)
        local head = s(40) + s(30)
        local panel = s(64)
        local bs = math.min(self.W, self.H - head - self.tool_h - panel)
        bs = bs - bs % 8
        self.board = Board:new{ size = bs }
        self.diffs = {}
        local app = self.app
        if not app._lpnet or app._lpnet.token ~= app:lichessToken() then
            if app._lpnet then app._lpnet:close() end
            app._lpnet = Net.new(app:lichessToken())
        end
        self.net = app._lpnet
        self:loadCurrent()
    end

    function Play:onClose()
        if self.run then self.run.gen = self.run.gen + 1 end
        self:sendResults()
        if self.onDone then self.onDone() end
    end

    function Play:loadCurrent()
        local d = LP.ensure(self.app.data)
        self.selected, self.targets, self.arrow, self.mark = nil, nil, nil, nil
        self.hint_stage = 0
        local p = d.batch[d.idx]
        if not p then
            self.run = nil
            self:fetch()
            return
        end
        self.run = Run.new(p, function(t, fn) UIManager:scheduleIn(t, fn) end, function(ev) self:onRun(ev) end)
        if LP.remaining(d) <= LP.REFILL and #d.queue == 0 and not self.loading then
            -- on prépare la suite en arrière-plan, sans gêner
            UIManager:scheduleIn(1.5, function()
                if self.closed or self.loading then return end
                if LP.remaining(LP.ensure(self.app.data)) <= LP.REFILL then
                    self.app:whenOnline(function() pcall(self.net.fetch, self.net, d) end)
                end
            end)
        end
    end

    function Play:fetch()
        if self.loading then return end
        self.loading = true
        self.error = nil
        self:refresh("ui")
        UIManager:nextTick(function()
            self.app:whenOnline(function()
                if self.closed then return end
                local d = LP.ensure(self.app.data)
                local n, err = self.net:fetch(d)
                self.loading = false
                if not n then
                    self.error = err
                else
                    self.app:save()
                end
                if d.batch[d.idx] then self:loadCurrent() end
                self:refresh("ui")
            end)
        end)
    end

    -- Envoi des résultats à Lichess (le classement change tout de suite)
    function Play:sendResults(cb)
        local d = LP.ensure(self.app.data)
        if #d.queue == 0 or not self.net.token or self.net.no_scope then
            if cb then cb() end
            return
        end
        self.app:whenOnline(function()
            local ok, err = self.net:flush(d, self.diffs)
            self.send_error = not ok and err or nil
            self.app:save()
            if cb then cb() end
        end)
    end

    function Play:onRun(ev)
        if self.closed then return end
        local run = self.run
        if ev == "resolu" or ev == "rate" or ev == "vu" then
            self:record()
        end
        if ev ~= "coup" then self.arrow, self.mark = nil, nil end
        self:refresh("ui")
        if ev == "resolu" or ev == "rate" then
            UIManager:nextTick(function()
                if self.closed then return end
                self:sendResults(function()
                    if not self.closed and self.run == run then self:refresh("ui") end
                end)
            end)
        end
    end

    -- Le résultat du premier essai part dans la file d'envoi (une seule fois par problème)
    function Play:record()
        local run = self.run
        if run.recorded or run.result == nil then return end
        run.recorded = true
        local d = LP.ensure(self.app.data)
        d.queue[#d.queue + 1] = { id = run.p.id, win = run.result, angle = run.p.angle or d.angle }
        if run.result then
            d.won = d.won + 1
            d.streak = d.streak + 1
        else
            d.lost = d.lost + 1
            d.streak = 0
        end
        self.app:save()
    end

    function Play:next()
        local d = LP.ensure(self.app.data)
        if self.run and self.run.result == nil then
            -- passé sans le jouer : rien n'est envoyé à Lichess
            self.run.gen = self.run.gen + 1
        end
        d.idx = d.idx + 1
        self.app:save()
        self:loadCurrent()
        self:refresh("ui")
    end

    function Play:hint()
        local run = self.run
        local m = run and run:nextMove()
        if not m or run.pos.turn ~= run.side then return end
        run:decide(false)
        self:record()
        self.hint_stage = self.hint_stage + 1
        if self.hint_stage == 1 then
            self.mark = { sq = m.from, rgb = UI.GOLD, gray = 0xC8 }
            self.arrow = nil
            run.message = "Indice : la pièce à jouer est marquée. Touchez encore « Indice » pour voir le coup."
        else
            self.mark = nil
            self.arrow = { from = m.from, to = m.to, rgb = { 120, 190, 120 }, gray = 0x60 }
            run.message = "Le coup à jouer : " .. run.pos:san(m) .. "."
        end
        self:refresh("ui")
        UIManager:nextTick(function() if not self.closed then self:sendResults() end end)
    end

    function Play:solution()
        local run = self.run
        if not run then return end
        self.arrow, self.mark = nil, nil
        self.selected, self.targets = nil, nil
        run:showSolution()
        self:record()
        self:refresh("ui")
        UIManager:nextTick(function() if not self.closed then self:sendResults() end end)
    end

    function Play:onNextKey() if self.run and self.run.state ~= "jeu" then self:next() end end
    function Play:onSwipe(dir) if dir == "west" then self:onNextKey() end end

    function Play:draw(bb)
        local app = self.app
        local d = LP.ensure(app.data)
        local W, mg = self.W, self.mg
        local y = self:header(bb, "Problème Lichess", "Thèmes", function() self:close() end)
        local run = self.run
        if not run then
            y = y + s(40)
            local f = UI.face(17, true)
            local txt = self.loading and "Chargement des problèmes depuis Lichess…" or (self.error or "Aucun problème.")
            for _, l in ipairs(UI.wrap(f, txt, W - s(60))) do
                UI.textCentered(bb, f, l, W / 2, y)
                y = y + UI.lineHeight(f)
            end
            if not self.loading then
                y = y + s(20)
                local bw = s(220)
                UI.pill(bb, (W - bw) / 2, y, bw, s(44), "Réessayer", UI.face(16), { dark = true })
                self:region((W - bw) / 2, y, bw, s(44), function() self:fetch() end)
            end
            return
        end
        local p = run.p
        local fb = UI.face(16, true)
        local goal = "Trouvez le meilleur coup pour les " .. (run.side == "w" and "Blancs" or "Noirs")
        if run.state == "attente" then goal = "L'adversaire répond…" end
        UI.textCentered(bb, fb, UI.ellipsize(fb, goal, W - s(150)), W / 2, y + s(2))
        if p.rating then UI.text(bb, UI.face(13), "★ " .. p.rating, mg * 3, y + s(5), UI.DIM) end
        UI.textRight(bb, UI.face(13), LP.remaining(d) .. " en réserve", W - mg * 3, y + s(5), UI.GRAY)
        y = y + s(28)

        local b = self.board
        b.pos = run.pos
        b.flipped = run.side == "b"
        b.last_move = run.last
        b.selected, b.targets = self.selected, self.targets
        b.arrows, b.marks, b.badges = {}, {}, {}
        if self.arrow then b.arrows[1] = self.arrow end
        if self.mark then b.marks[1] = self.mark end
        local bx = math.floor((W - b.size) / 2)
        b:paintTo(bb, bx, y)
        self:region(bx, y, b.size, b.size, function(ges)
            local sq = b:squareAt(ges.pos.x, ges.pos.y)
            if sq then self:onSquare(sq) end
        end)
        y = y + b.size + s(4)

        local items
        if run.state == "resolu" then
            items = { { "Rejouer", function() run:reset(); self:refresh("ui") end }, { "Suivant ›", function() self:next() end, true } }
        elseif run.state == "rate" then
            items = { { "Réessayer", function() run:retry() end, true }, { "Solution", function() self:solution() end },
                { "Suivant ›", function() self:next() end } }
        elseif run.state == "solution" then
            items = { { "Suivant ›", function() self:next() end, true } }
        else
            items = { { "Indice", function() self:hint() end }, { "Solution", function() self:solution() end },
                { "Passer ›", function() self:next() end } }
        end
        local f = UI.face(17)
        local widths, total = {}, 0
        for i, it in ipairs(items) do
            widths[i] = UI.textWidth(f, it[1]) + s(30)
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

        -- texte
        local px = mg * 3
        local pw = W - 2 * px
        local lines = {}
        local function add(t) lines[#lines + 1] = t end
        add(run.message or "Touchez une pièce puis sa case d'arrivée.")
        local over = run.state == "resolu" or run.state == "solution" or run.state == "rate"
        if run.result ~= nil and run.recorded then
            local diff = self.diffs[p.id]
            local r = (run.result and "Réussi" or "Raté") .. " au premier essai"
            if diff then
                r = r .. " · classement " .. (diff >= 0 and "+" or "") .. diff .. (d.rating and (" → " .. d.rating) or "")
            elseif self.send_error then
                r = r .. " · " .. self.send_error
            elseif self.net.token and not self.net.no_scope then
                r = r .. " · envoi à Lichess…"
            end
            add(r)
        end
        if over then
            local th = {}
            for _, t in ipairs(p.themes or {}) do th[#th + 1] = LP.themeName(t) end
            if #th > 0 then add("Thèmes : " .. table.concat(th, ", ")) end
            if run.state ~= "rate" then add("Solution : " .. LP.solutionText(p)) end
            if p.white and p.black then add("Partie : " .. p.white .. " – " .. p.black .. (p.clock and (", " .. p.clock) or "")) end
        else
            add(LP.themeName(d.angle) .. " · " .. LP.difficultyName(d.difficulty) .. " · " .. ratingLine(d, self.net))
        end
        local text = table.concat(lines, "\n")
        if text ~= self._last_text then self._last_text = text; self.page = 1 end
        self:pagedText(bb, UI.face(15), text, px, y, pw)
    end

    function Play:onSquare(sq)
        local run = self.run
        if not run or run.state ~= "jeu" or run.pos.turn ~= run.side then return end
        local pos = run.pos
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
                                run:playerMove(mv)
                            end }
                        end
                    end
                end
                dialog = ButtonDialog:new{ title = "Promotion du pion", buttons = { row } }
                UIManager:show(dialog)
            elseif #cands == 1 then
                run:playerMove(cands[1])
            end
            return
        end
        local pc = pos.board[sq]
        if pc and Chess.colorOf(pc) == pos.turn and sq ~= self.selected then
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

return LP
