--[[
  The season: a real 365-day calendar, 10 tournaments in 10 months,
  Candidates Tournament, World Championship on day 364,
  circuit players, trophies and record.
]]

local AI = require("cc_ai")
local Names = require("cc_names")
local T = require("cc_tournament")

local Career = {}

Career.DAY = 86400
Career.TOURNAMENT_DAYS = 304   -- 10 months
Career.WC_DAY = 364
Career.MONTH_DAYS = 30.4

---------------------------------------------------------------------------
-- Circuit players
---------------------------------------------------------------------------

local function pickPersona(rnd)
    local weights = { attaquant = 3, positionnel = 3, solide = 2, tacticien = 3, zeitnot = 2, blitzeur = 2, equilibre = 3 }
    local total = 0
    for _, w in pairs(weights) do total = total + w end
    local r = rnd() * total
    for _, id in ipairs(AI.PERSONA_IDS) do
        r = r - weights[id]
        if r <= 0 then return id end
    end
    return "equilibre"
end

function Career.makePool(rnd, n)
    rnd = rnd or math.random
    local pool, used = {}, {}
    n = n or 150
    for i = 1, n do
        local name, country = Names.random(rnd, used)
        local elo = math.floor(250 + (2700 - 250) * (i - 1) / (n - 1) + (rnd() - 0.5) * 30)
        pool[#pool + 1] = { id = "p" .. i, name = name, country = country, elo = elo, persona = pickPersona(rnd) }
    end
    return pool
end

function Career.poolById(career)
    local m = {}
    for _, p in ipairs(career.pool) do m[p.id] = p end
    return m
end

function Career.npc(career, id)
    for _, p in ipairs(career.pool) do if p.id == id then return p end end
    return nil
end

---------------------------------------------------------------------------
-- Season
---------------------------------------------------------------------------

local function newSeason(career, n, rnd)
    -- the reigning World Champion: a circuit player chosen for the season
    local champ = career.pool[math.floor(rnd() * #career.pool) + 1]
    return {
        n = n,
        start = nil,          -- set when the first tournament starts
        trophies = {},        -- [city] = { day = , time = }
        attempts = {},        -- [city] = number of attempts
        active = nil,         -- tournament in progress
        candidates = { attempts = 0, won = false },
        champion_id = champ.id,
        wc = nil,             -- championship match (played or simulated)
        finished = false,
    }
end

function Career.ensure(data, rnd)
    rnd = rnd or math.random
    data.career = data.career or {}
    local c = data.career
    if not c.pool then c.pool = Career.makePool(rnd) end
    if not c.season then c.season = newSeason(c, 1, rnd) end
    c.palmares = c.palmares or {}
    return c
end

function Career.newSeason(career, rnd)
    rnd = rnd or math.random
    local n = (career.season and career.season.n or 0) + 1
    career.season = newSeason(career, n, rnd)
end

function Career.day(season, now)
    if not season.start then return nil end
    return math.floor((now - season.start) / Career.DAY)
end

--[[
  Season phase:
   "attente"   : no tournament started yet
   "tournois"  : the first 10 months
   "fin"       : the last 2 months (Candidates or casual games)
   "monde"     : from day 364 (World Championship)
]]
function Career.phase(season, now)
    local d = Career.day(season, now)
    if not d then return "attente" end
    if d < Career.TOURNAMENT_DAYS then return "tournois" end
    if d < Career.WC_DAY then return "fin" end
    return "monde"
end

local function plural(n, s, p) return n .. " " .. (n > 1 and (p or (s .. "s")) or s) end

-- Countdown text for the 10 tournaments
function Career.countdownText(season, now)
    local d = Career.day(season, now)
    if not d then
        return "The 10-month countdown starts when you enter your first tournament."
    end
    local left = Career.TOURNAMENT_DAYS - d
    if left <= 0 then return "The tournament season is over." end
    local months = math.floor(left / Career.MONTH_DAYS)
    local days = math.floor(left - months * Career.MONTH_DAYS)
    if months > 0 then
        return "You have " .. plural(months, "month") .. (days > 0 and (" and " .. plural(days, "day")) or "")
            .. " left to win all 10 trophies."
    end
    return "You have " .. plural(math.max(1, left), "day") .. " left to win all 10 trophies."
end

function Career.daysToWorld(season, now)
    local d = Career.day(season, now)
    if not d then return nil end
    return math.max(0, Career.WC_DAY - d)
end

function Career.trophyCount(season)
    local n = 0
    for _, c in ipairs(T.CITIES) do if season.trophies[c.id] then n = n + 1 end end
    return n
end

function Career.allTrophiesInTime(season)
    if Career.trophyCount(season) < #T.CITIES then return false end
    for _, c in ipairs(T.CITIES) do
        local tr = season.trophies[c.id]
        if not tr or (tr.started_day or tr.day) >= Career.TOURNAMENT_DAYS then return false end
    end
    return true
end

---------------------------------------------------------------------------
-- Opening tournaments
---------------------------------------------------------------------------

-- Open status: "gagne" (won), "en_cours" (in progress), "ouvert" (open), "bloque" (another tournament running), "ferme" (closed)
function Career.openStatus(career, cityId, now)
    local s = career.season
    if s.trophies[cityId] then return "gagne" end
    if s.active and s.active.kind == "open" and s.active.city == cityId then return "en_cours" end
    local ph = Career.phase(s, now)
    if ph ~= "attente" and ph ~= "tournois" then return "ferme" end
    if s.active then return "bloque" end
    return "ouvert"
end

function Career.startOpen(career, cityId, me, now, rnd)
    local s = career.season
    if Career.openStatus(career, cityId, now) ~= "ouvert" then return nil end
    if not s.start then s.start = now end
    s.attempts[cityId] = (s.attempts[cityId] or 0) + 1
    local t = T.newOpen(cityId, me, career.pool, rnd)
    t.started_day = Career.day(s, now)
    s.active = t
    return t
end

-- "verrouille" (locked), "ouvert", "en_cours", "gagne", "ferme"
function Career.candidatesStatus(career, now)
    local s = career.season
    if s.candidates.won then return "gagne" end
    if s.active and s.active.kind == "candidats" then return "en_cours" end
    if not Career.allTrophiesInTime(s) then return "verrouille" end
    local ph = Career.phase(s, now)
    if ph == "monde" then return "ferme" end
    if s.active then return "bloque" end
    return "ouvert"
end

function Career.startCandidates(career, me, now, rnd)
    local s = career.season
    if Career.candidatesStatus(career, now) ~= "ouvert" then return nil end
    s.candidates.attempts = (s.candidates.attempts or 0) + 1
    local t = T.newCandidates(me, career.pool, rnd, { s.champion_id })
    s.active = t
    return t
end

--[[
  World Championship:
   "a_venir"    : not day 364 yet
   "qualifie"   : you have your ticket, the match is waiting (or in progress)
   "spectateur" : you are not qualified, the match is simulated
   "termine"    : over
]]
function Career.worldStatus(career, now)
    local s = career.season
    if s.wc and s.wc.done then return "termine" end
    if s.active and s.active.kind == "monde" then return "qualifie" end
    if Career.phase(s, now) ~= "monde" then return "a_venir" end
    if s.candidates.won then return "qualifie" end
    return "spectateur"
end

function Career.startWorld(career, me, now, rnd)
    local s = career.season
    if Career.worldStatus(career, now) ~= "qualifie" or s.active then return s.active end
    local champ = Career.npc(career, s.champion_id)
    -- a champion slightly stronger than you
    champ.elo = math.max(champ.elo, me.elo + 50)
    if champ.elo > me.elo + 120 then champ.elo = me.elo + 60 end
    local t = T.newWorld(me, champ)
    t.first_white = (rnd or math.random)() < 0.5 and 1 or 2
    s.active = t
    return t
end

-- You are not qualified: simulate the match between the champion and the Candidates winner
function Career.simulateWorld(career, me, rnd)
    rnd = rnd or math.random
    local s = career.season
    if s.wc then return s.wc end
    local champ = Career.npc(career, s.champion_id)
    -- the Candidates Tournament without you
    local field = {}
    local byElo = {}
    for _, p in ipairs(career.pool) do
        if p.id ~= champ.id then byElo[#byElo + 1] = p end
    end
    table.sort(byElo, function(a, b) return math.abs(a.elo - (me.elo + 85)) < math.abs(b.elo - (me.elo + 85)) end)
    for i = 1, 8 do
        local p = byElo[i]
        field[i] = { id = p.id, name = p.name, elo = p.elo, persona = p.persona }
    end
    local cand = T.simulateWhole(field, 6, rnd)
    local match = T.simulateMatch(
        { name = champ.name, elo = math.max(champ.elo, cand.elo + 30), persona = champ.persona },
        { name = cand.name, elo = cand.elo, persona = cand.persona }, 13, rnd)
    s.wc = { simulated = true, candidate = cand.name, champion = champ.name, match = match, done = true,
        new_champion = match.winner }
    return s.wc
end

---------------------------------------------------------------------------
-- End of a tournament
---------------------------------------------------------------------------

-- Returns a short text describing what was won (or nil)
function Career.onTournamentFinished(career, t, now)
    local s = career.season
    local won = t.winner == 1
    local rows = T.standings(t)
    local myRank
    for _, r in ipairs(rows) do if r.idx == 1 then myRank = r.rank end end
    local msg
    if t.kind == "open" then
        if won then
            s.trophies[t.city] = { day = Career.day(s, now) or 0, started_day = t.started_day or 0, time = now }
            local c = T.city(t.city)
            msg = "You win the " .. t.name .. "! The " .. c.name .. " trophy joins your shelf."
            career.palmares[#career.palmares + 1] = { season = s.n, title = t.name, time = now }
        end
    elseif t.kind == "candidats" then
        if won then
            s.candidates.won = true
            msg = "You win the Candidates Tournament! Your ticket to the World Championship is booked."
            career.palmares[#career.palmares + 1] = { season = s.n, title = "Candidates Tournament", time = now }
        end
    elseif t.kind == "monde" then
        local pts = T.points(t)
        s.wc = { simulated = false, done = true, me_won = won, pa = pts[1], pb = pts[2],
            champion = t.players[2].name, retained = t.retained }
        if won then
            msg = "You are the World Champion!"
            career.palmares[#career.palmares + 1] = { season = s.n, title = "World Champion", time = now }
        end
    end
    s.last = { kind = t.kind, name = t.name, rank = myRank, won = won, time = now }
    s.active = nil
    return msg, myRank
end

return Career
