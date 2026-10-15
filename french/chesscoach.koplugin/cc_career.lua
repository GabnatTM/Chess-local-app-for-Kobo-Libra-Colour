--[[
  La saison : calendrier réel de 365 jours, 10 tournois en 10 mois,
  tournoi des candidats, championnat du monde au 364e jour,
  joueurs du circuit, trophées et palmarès.
]]

local AI = require("cc_ai")
local Names = require("cc_names")
local T = require("cc_tournament")

local Career = {}

Career.DAY = 86400
Career.TOURNAMENT_DAYS = 304   -- 10 mois
Career.WC_DAY = 364
Career.MONTH_DAYS = 30.4

---------------------------------------------------------------------------
-- Joueurs du circuit
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
-- Saison
---------------------------------------------------------------------------

local function newSeason(career, n, rnd)
    -- le champion du monde en titre : un joueur du circuit, désigné pour la saison
    local champ = career.pool[math.floor(rnd() * #career.pool) + 1]
    return {
        n = n,
        start = nil,          -- fixé au lancement du premier tournoi
        trophies = {},        -- [ville] = { day = , time = }
        attempts = {},        -- [ville] = nombre de tentatives
        active = nil,         -- tournoi en cours
        candidates = { attempts = 0, won = false },
        champion_id = champ.id,
        wc = nil,             -- match du championnat (joué ou simulé)
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
  Phase de la saison :
   "attente"   : aucun tournoi encore lancé
   "tournois"  : les 10 premiers mois
   "fin"       : les 2 derniers mois (candidats ou parties libres)
   "monde"     : à partir du 364e jour (championnat du monde)
]]
function Career.phase(season, now)
    local d = Career.day(season, now)
    if not d then return "attente" end
    if d < Career.TOURNAMENT_DAYS then return "tournois" end
    if d < Career.WC_DAY then return "fin" end
    return "monde"
end

local function plural(n, s, p) return n .. " " .. (n > 1 and (p or (s .. "s")) or s) end

-- Texte du compte à rebours pour les 10 tournois
function Career.countdownText(season, now)
    local d = Career.day(season, now)
    if not d then
        return "Le compte à rebours de 10 mois démarrera au lancement de votre premier tournoi."
    end
    local left = Career.TOURNAMENT_DAYS - d
    if left <= 0 then return "La saison des tournois est terminée." end
    local months = math.floor(left / Career.MONTH_DAYS)
    local days = math.floor(left - months * Career.MONTH_DAYS)
    if months > 0 then
        return "Il vous reste " .. plural(months, "mois", "mois") .. (days > 0 and (" et " .. plural(days, "jour")) or "")
            .. " pour gagner les 10 trophées."
    end
    return "Il vous reste " .. plural(math.max(1, left), "jour") .. " pour gagner les 10 trophées."
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
-- Ouverture des tournois
---------------------------------------------------------------------------

-- État d'un open : "gagne", "en_cours", "ouvert", "bloque" (autre tournoi en cours), "ferme"
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

-- "verrouille", "ouvert", "en_cours", "gagne", "ferme"
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
  Championnat du monde :
   "a_venir"    : pas encore le 364e jour
   "qualifie"   : vous avez votre ticket, le match vous attend (ou est en cours)
   "spectateur" : vous n'êtes pas qualifié, le match est simulé
   "termine"
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
    -- un champion un peu plus fort que vous
    champ.elo = math.max(champ.elo, me.elo + 50)
    if champ.elo > me.elo + 120 then champ.elo = me.elo + 60 end
    local t = T.newWorld(me, champ)
    t.first_white = (rnd or math.random)() < 0.5 and 1 or 2
    s.active = t
    return t
end

-- Vous n'êtes pas qualifié : on simule le match entre le champion et le vainqueur des candidats
function Career.simulateWorld(career, me, rnd)
    rnd = rnd or math.random
    local s = career.season
    if s.wc then return s.wc end
    local champ = Career.npc(career, s.champion_id)
    -- le tournoi des candidats sans vous
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
-- Fin d'un tournoi
---------------------------------------------------------------------------

-- Renvoie un petit texte décrivant ce qui a été gagné (ou nil)
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
            msg = "Vous remportez l'" .. t.name .. " ! Le trophée de " .. c.name .. " rejoint votre étagère."
            career.palmares[#career.palmares + 1] = { season = s.n, title = t.name, time = now }
        end
    elseif t.kind == "candidats" then
        if won then
            s.candidates.won = true
            msg = "Vous gagnez le tournoi des candidats ! Votre ticket pour le championnat du monde est réservé."
            career.palmares[#career.palmares + 1] = { season = s.n, title = "Tournoi des candidats", time = now }
        end
    elseif t.kind == "monde" then
        local pts = T.points(t)
        s.wc = { simulated = false, done = true, me_won = won, pa = pts[1], pb = pts[2],
            champion = t.players[2].name, retained = t.retained }
        if won then
            msg = "Vous êtes champion du monde !"
            career.palmares[#career.palmares + 1] = { season = s.n, title = "Champion du monde", time = now }
        end
    end
    s.last = { kind = t.kind, name = t.name, rank = myRank, won = won, time = now }
    s.active = nil
    return msg, myRank
end

return Career
