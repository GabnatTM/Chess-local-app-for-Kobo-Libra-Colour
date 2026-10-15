--[[
  Tournois : système suisse (6 rondes, 8 joueurs), match du championnat
  du monde (13 parties + départage), simulation des autres parties.
  Logique pure, sans affichage.
]]

local AI = require("cc_ai")

local T = {}

T.CITIES = {
    { id = "bruxelles", name = "Bruxelles", country = "be", art = "atomium", offset = -40, color = { 168, 200, 232 } },
    { id = "paris", name = "Paris", country = "fr", art = "eiffel", offset = -30, color = { 232, 190, 200 } },
    { id = "londres", name = "Londres", country = "uk", art = "bigben", offset = -20, color = { 200, 210, 230 } },
    { id = "madrid", name = "Madrid", country = "es", art = "alcala", offset = -10, color = { 240, 214, 160 } },
    { id = "rome", name = "Rome", country = "it", art = "colisee", offset = 0, color = { 236, 200, 170 } },
    { id = "berlin", name = "Berlin", country = "de", art = "brandebourg", offset = 10, color = { 210, 220, 200 } },
    { id = "budapest", name = "Budapest", country = "hu", art = "parlement", offset = 20, color = { 220, 200, 232 } },
    { id = "reykjavik", name = "Reykjavik", country = "is", art = "eglise", offset = 30, color = { 190, 222, 230 } },
    { id = "buenosaires", name = "Buenos Aires", country = "ar", art = "obelisque", offset = 40, color = { 180, 214, 236 } },
    { id = "tokyo", name = "Tokyo", country = "jp", art = "pagode", offset = 55, color = { 240, 196, 190 } },
}

function T.city(id)
    for i, c in ipairs(T.CITIES) do
        if c.id == id then return c, i end
    end
    return nil
end

T.KIND_NAMES = { open = "Open", candidats = "Tournoi des candidats", monde = "Championnat du monde" }

---------------------------------------------------------------------------
-- Choix des adversaires
---------------------------------------------------------------------------

local function pickNear(pool, target, n, exclude, rnd, spread)
    local cands = {}
    for _, p in ipairs(pool) do
        if not exclude[p.id] then cands[#cands + 1] = p end
    end
    table.sort(cands, function(a, b) return math.abs(a.elo - target) < math.abs(b.elo - target) end)
    local window = {}
    for i = 1, math.min(#cands, spread or (n * 2)) do window[i] = cands[i] end
    local res = {}
    while #res < n and #window > 0 do
        local i = math.floor(rnd() * #window) + 1
        res[#res + 1] = table.remove(window, i)
    end
    return res
end

local function npcEntry(p)
    return { id = p.id, name = p.name, elo = p.elo, persona = p.persona, country = p.country }
end

local function newState(kind, name, rounds, tc, players, extra)
    local t = {
        kind = kind, name = name, rounds = rounds, tc = tc,
        players = players, round = 1, pairings = {}, finished = false,
        created = os.time(),
    }
    for k, v in pairs(extra or {}) do t[k] = v end
    return t
end

function T.newOpen(cityId, me, pool, rnd)
    rnd = rnd or math.random
    local city = T.city(cityId)
    local target = me.elo + (city.offset or 0)
    local exclude = {}
    local opps = pickNear(pool, target, 7, exclude, rnd, 14)
    local players = { { id = "moi", name = me.name or "Vous", elo = me.elo, me = true } }
    for _, p in ipairs(opps) do players[#players + 1] = npcEntry(p) end
    return newState("open", "Open de " .. city.name, 6, { base = 600, inc = 5 }, players, { city = cityId })
end

function T.newCandidates(me, pool, rnd, excludeIds)
    rnd = rnd or math.random
    local exclude = {}
    for _, id in ipairs(excludeIds or {}) do exclude[id] = true end
    local opps = pickNear(pool, me.elo + 85, 7, exclude, rnd, 12)
    local players = { { id = "moi", name = me.name or "Vous", elo = me.elo, me = true } }
    for _, p in ipairs(opps) do players[#players + 1] = npcEntry(p) end
    return newState("candidats", "Tournoi des candidats", 6, { base = 900, inc = 10 }, players)
end

function T.newWorld(me, champion)
    local players = {
        { id = "moi", name = me.name or "Vous", elo = me.elo, me = true },
        npcEntry(champion),
    }
    players[2].champion = true
    return newState("monde", "Championnat du monde", 13, { base = 900, inc = 10 }, players,
        { first_white = 1, tiebreak_tc = { base = 180, inc = 5 } })
end

---------------------------------------------------------------------------
-- Classement
---------------------------------------------------------------------------

local function scoreOf(res, asWhite)
    if res == "1/2-1/2" then return 0.5 end
    if res == "1-0" then return asWhite and 1 or 0 end
    if res == "0-1" then return asWhite and 0 or 1 end
    return nil
end
T.scoreOf = scoreOf

function T.points(t)
    local pts = {}
    for i = 1, #t.players do pts[i] = 0 end
    for r, list in pairs(t.pairings) do
        if not (t.kind == "monde" and r > t.rounds) then
            for _, p in ipairs(list) do
                if p.res then
                    pts[p.w] = pts[p.w] + scoreOf(p.res, true)
                    pts[p.b] = pts[p.b] + scoreOf(p.res, false)
                end
            end
        end
    end
    return pts
end

function T.opponents(t, i)
    local opp = {}
    for _, list in pairs(t.pairings) do
        for _, p in ipairs(list) do
            if p.w == i then opp[#opp + 1] = p.b elseif p.b == i then opp[#opp + 1] = p.w end
        end
    end
    return opp
end

function T.standings(t)
    local pts = T.points(t)
    local rows = {}
    for i, pl in ipairs(t.players) do
        local buch = 0
        for _, o in ipairs(T.opponents(t, i)) do buch = buch + pts[o] end
        rows[#rows + 1] = { idx = i, player = pl, pts = pts[i], buch = buch, elo = pl.elo }
    end
    table.sort(rows, function(a, b)
        if a.pts ~= b.pts then return a.pts > b.pts end
        if a.buch ~= b.buch then return a.buch > b.buch end
        return a.elo > b.elo
    end)
    for r, row in ipairs(rows) do row.rank = r end
    return rows
end

---------------------------------------------------------------------------
-- Appariements
---------------------------------------------------------------------------

local function colorHistory(t, i)
    local whites, last = 0, nil
    for r = 1, t.round - 1 do
        for _, p in ipairs(t.pairings[r] or {}) do
            if p.w == i then whites = whites + 1; last = "w" end
            if p.b == i then last = "b" end
        end
    end
    return whites, last
end

local function assignColors(t, a, b, rnd)
    local wa, la = colorHistory(t, a)
    local wb, lb = colorHistory(t, b)
    if wa < wb then return a, b end
    if wb < wa then return b, a end
    if la == "b" and lb ~= "b" then return a, b end
    if lb == "b" and la ~= "b" then return b, a end
    if rnd() < 0.5 then return a, b end
    return b, a
end

function T.pairRound(t, rnd)
    rnd = rnd or math.random
    if t.pairings[t.round] then return t.pairings[t.round] end
    local list = {}
    if t.kind == "monde" then
        local meWhite
        if t.round > t.rounds then
            meWhite = rnd() < 0.5
        else
            meWhite = (t.round % 2 == 1) == (t.first_white == 1)
        end
        list[1] = meWhite and { w = 1, b = 2 } or { w = 2, b = 1 }
        t.pairings[t.round] = list
        return list
    end

    local n = #t.players
    if t.round == 1 then
        local order = {}
        for i = 1, n do order[i] = i end
        table.sort(order, function(a, b) return t.players[a].elo > t.players[b].elo end)
        for k = 1, n / 2 do
            local a, b = order[k], order[k + n / 2]
            local w, bl
            if k % 2 == 1 then w, bl = a, b else w, bl = b, a end
            list[#list + 1] = { w = w, b = bl }
        end
        t.pairings[1] = list
        return list
    end

    local rows = T.standings(t)
    local rank, pts = {}, {}
    for _, row in ipairs(rows) do rank[row.idx] = row.rank; pts[row.idx] = row.pts end
    local played = {}
    for i = 1, n do played[i] = {} end
    for _, l in pairs(t.pairings) do
        for _, p in ipairs(l) do played[p.w][p.b] = true; played[p.b][p.w] = true end
    end
    local order = {}
    for _, row in ipairs(rows) do order[#order + 1] = row.idx end

    local best, bestCost = nil, math.huge
    local used, cur = {}, {}
    local function search(cost)
        if cost >= bestCost then return end
        local first
        for _, i in ipairs(order) do if not used[i] then first = i break end end
        if not first then
            bestCost = cost
            best = {}
            for k, v in ipairs(cur) do best[k] = v end
            return
        end
        used[first] = true
        for _, j in ipairs(order) do
            if not used[j] then
                local c = (played[first][j] and 1000 or 0)
                    + (pts[first] - pts[j]) ^ 2 * 10 + math.abs(rank[first] - rank[j]) * 0.5
                used[j] = true
                cur[#cur + 1] = { first, j }
                search(cost + c)
                cur[#cur] = nil
                used[j] = nil
            end
        end
        used[first] = nil
    end
    search(0)
    for _, pr in ipairs(best) do
        local w, b = assignColors(t, pr[1], pr[2], rnd)
        list[#list + 1] = { w = w, b = b }
    end
    t.pairings[t.round] = list
    return list
end

-- Votre partie de la ronde en cours : pairing, votre couleur, index adversaire
function T.myPairing(t)
    local list = t.pairings[t.round]
    if not list then return nil end
    for _, p in ipairs(list) do
        if p.w == 1 then return p, "w", p.b end
        if p.b == 1 then return p, "b", p.w end
    end
end

function T.tcForRound(t)
    if t.kind == "monde" and t.round > t.rounds then return t.tiebreak_tc end
    return t.tc
end

---------------------------------------------------------------------------
-- Simulation des parties entre joueurs du circuit
---------------------------------------------------------------------------

function T.simulateGame(a, b, rnd)
    rnd = rnd or math.random
    local e = 1 / (1 + 10 ^ ((b.elo - a.elo) / 400))
    local da = AI.persona(a.persona).draw or 0.3
    local db = AI.persona(b.persona).draw or 0.3
    local drawP = (0.12 + (da + db) * 0.2) * (1 - math.abs(e - 0.5))
    local winA = math.max(0.02, e - drawP / 2)
    local r = rnd()
    if r < winA then return "1-0" end
    if r < winA + drawP then return "1/2-1/2" end
    return "0-1"
end

local function eloUpdate(ra, rb, score, k)
    local e = 1 / (1 + 10 ^ ((rb - ra) / 400))
    return ra + (k or 20) * (score - e)
end

--[[
  Enregistre votre résultat (res du point de vue des blancs : "1-0"…),
  simule les autres parties de la ronde, passe à la ronde suivante.
  poolById : table id -> joueur du circuit (pour mettre à jour leur Elo)
  Renvoie true si le tournoi est terminé.
]]
function T.recordResult(t, res, poolById, rnd)
    rnd = rnd or math.random
    local p = T.myPairing(t)
    if not p then return t.finished end
    p.res = res
    for _, q in ipairs(t.pairings[t.round]) do
        if not q.res then
            q.res = T.simulateGame(t.players[q.w], t.players[q.b], rnd)
        end
        -- Elo des joueurs du circuit
        for _, side in ipairs({ "w", "b" }) do
            local idx = q[side]
            local other = side == "w" and q.b or q.w
            local pl = t.players[idx]
            if not pl.me and poolById and poolById[pl.id] then
                local sc = scoreOf(q.res, side == "w")
                local npc = poolById[pl.id]
                npc.elo = math.floor(eloUpdate(npc.elo, t.players[other].elo, sc, 16) + 0.5)
            end
        end
    end
    t.round = t.round + 1
    T.checkFinished(t)
    return t.finished
end

function T.checkFinished(t)
    if t.kind == "monde" then
        local pts = T.points(t)
        local half = t.rounds / 2
        local playedMain = math.min(t.round - 1, t.rounds)
        if pts[1] > half or pts[2] > half then
            t.finished = true
            t.winner = pts[1] > pts[2] and 1 or 2
        elseif playedMain >= t.rounds then
            if pts[1] ~= pts[2] then
                t.finished = true
                t.winner = pts[1] > pts[2] and 1 or 2
            elseif t.round > t.rounds + 1 then
                -- départage joué
                local tb = t.pairings[t.rounds + 1][1]
                local s1 = scoreOf(tb.res, tb.w == 1)
                t.finished = true
                if s1 == 1 then t.winner = 1 elseif s1 == 0 then t.winner = 2
                else t.winner = 2; t.retained = true end -- le champion conserve son titre
            end
        end
        return t.finished
    end
    if t.round > t.rounds then
        t.finished = true
        t.winner = T.standings(t)[1].idx
    end
    return t.finished
end

-- Simule un tournoi complet entre joueurs du circuit (sans vous)
function T.simulateWhole(players, rounds, rnd)
    local t = newState("sim", "sim", rounds, nil, players)
    while t.round <= rounds do
        T.pairRound(t, rnd)
        for _, q in ipairs(t.pairings[t.round]) do
            q.res = T.simulateGame(t.players[q.w], t.players[q.b], rnd)
        end
        t.round = t.round + 1
    end
    return T.standings(t)[1].player, t
end

-- Simule un match du championnat du monde entre deux joueurs du circuit
function T.simulateMatch(a, b, rounds, rnd)
    local games = {}
    local pa, pb = 0, 0
    for r = 1, rounds do
        local white, black = a, b
        if r % 2 == 0 then white, black = b, a end
        local res = T.simulateGame(white, black, rnd)
        local sa = scoreOf(res, white == a)
        pa = pa + sa
        pb = pb + (1 - sa)
        games[#games + 1] = { white = white.name, black = black.name, res = res }
        if pa > rounds / 2 or pb > rounds / 2 then break end
    end
    local winner
    if pa > pb then winner = a elseif pb > pa then winner = b else winner = a end
    return { a = a.name, b = b.name, pa = pa, pb = pb, games = games, winner = winner.name }
end

return T
