--[[
  Choix du coup de l'IA : niveau (Elo 400 à 2500) et style de jeu.

  Stockfish analyse toujours à pleine force et propose plusieurs coups.
  On choisit ensuite parmi eux en imitant un joueur du niveau demandé :
  plus le niveau est bas, plus on accepte des coups imparfaits, et
  parfois une vraie bévue (comme un débutant).
  Le style donne un « goût » : préférer les échecs, les prises,
  le développement, la sécurité du roi, les pièges…
]]

local Chess = require("cc_chess")

local AI = {}

AI.MIN_ELO = 400
AI.MAX_ELO = 2500

AI.STYLES = {
    { id = "equilibre", name = "Équilibré",
      desc = "Joue de façon naturelle, sans préférence marquée." },
    { id = "attaquant", name = "Attaquant",
      desc = "Cherche les échecs, les prises et l'attaque du roi, quitte à prendre des risques." },
    { id = "stratege", name = "Stratège",
      desc = "Développe ses pièces, contrôle le centre et joue des coups calmes." },
    { id = "prudent", name = "Prudent",
      desc = "Met son roi à l'abri, échange quand il mène et évite les complications." },
    { id = "piegeur", name = "Piégeur",
      desc = "Tend des pièges : menaces sur les grosses pièces et coups surprenants." },
}

function AI.styleById(id)
    for _, s in ipairs(AI.STYLES) do
        if s.id == id then return s end
    end
    return AI.STYLES[1]
end

-- Probabilité de gagner (0..100) à partir d'une évaluation en centipions
function AI.winPercent(cp)
    if cp > 9000 then return 100 end
    if cp < -9000 then return 0 end
    return 50 + 50 * (2 / (1 + math.exp(-0.00368208 * cp)) - 1)
end

-- « Température » : tolérance aux coups imparfaits selon le niveau
local function temperature(elo)
    local t = (elo - AI.MIN_ELO) / (AI.MAX_ELO - AI.MIN_ELO)
    if t < 0 then t = 0 elseif t > 1 then t = 1 end
    return 25 * (0.02 ^ t) -- 25 à 400 Elo, 0.5 à 2500 Elo
end

-- Probabilité de faire une vraie bévue (coup au hasard)
local function blunderChance(elo)
    if elo >= 2300 then return 0 end
    local pts = { {400, 0.22}, {800, 0.10}, {1200, 0.045}, {1600, 0.015}, {2000, 0.004}, {2300, 0} }
    for i = 1, #pts - 1 do
        local a, b = pts[i], pts[i + 1]
        if elo <= b[1] then
            local k = (elo - a[1]) / (b[1] - a[1])
            if k < 0 then k = 0 end
            return a[2] + (b[2] - a[2]) * k
        end
    end
    return 0
end

-- Temps de réflexion conseillé (ms) selon le niveau
function AI.thinkTime(elo, base)
    base = base or 1000
    if elo >= 2200 then return base * 1.5 end
    if elo >= 1600 then return base end
    return math.max(500, base * 0.7)
end

-- Nombre de coups candidats à demander à Stockfish
function AI.multiPV(elo)
    if elo >= 2300 then return 3 end
    return 5
end

local function distance(a, b)
    return math.max(math.abs(Chess.fileOf(a) - Chess.fileOf(b)), math.abs(Chess.rankOf(a) - Chess.rankOf(b)))
end

local CENTER = { [27] = true, [28] = true, [35] = true, [36] = true } -- d4 e4 d5 e5

-- Bonus de style (en « points de pourcentage de gain »)
function AI.styleBonus(style, pos, m)
    if style == "equilibre" then return 0 end
    local us = pos.turn
    local them = Chess.other(us)
    local after = pos:makeMove(m)
    local gives_check = after:inCheck()
    local l = m.piece:lower()
    local opening = pos.fullmove <= 12
    local bonus = 0

    -- valeur des pièces adverses attaquées par la pièce déplacée
    local attacked_value = 0
    for _, s in ipairs(after:attacksFrom(m.to)) do
        local p = after.board[s]
        if p and Chess.colorOf(p) == them then
            local v = Chess.VALUES[p:lower()]
            if p:lower() == "k" then v = 4 end
            attacked_value = math.max(attacked_value, v)
        end
    end

    if style == "attaquant" then
        if gives_check then bonus = bonus + 3 end
        if m.captured then bonus = bonus + 1.5 end
        local ek = pos:kingSquare(them)
        if ek and l ~= "k" then
            local d0, d1 = distance(m.from, ek), distance(m.to, ek)
            if d1 < d0 then bonus = bonus + 1.2 end
        end
        if l == "p" and ek and math.abs(Chess.fileOf(m.to) - Chess.fileOf(ek)) <= 1 and not opening then
            bonus = bonus + 0.8 -- poussée de pions vers le roi adverse
        end
        if attacked_value >= 3 then bonus = bonus + 1 end
        if m.castle then bonus = bonus - 0.5 end
    elseif style == "stratege" then
        if not m.captured and not gives_check then bonus = bonus + 0.8 end
        if CENTER[m.to] and l == "p" then bonus = bonus + 1.5 end
        if opening and (l == "n" or l == "b") then
            local back = us == "w" and 0 or 7
            if Chess.rankOf(m.from) == back then bonus = bonus + 2 end
        end
        if opening and l == "q" then bonus = bonus - 2 end
        if m.castle then bonus = bonus + 1.5 end
        if l == "r" then
            -- tour sur colonne ouverte
            local open = true
            for r = 0, 7 do
                local p = after.board[r * 8 + Chess.fileOf(m.to)]
                if p and p:lower() == "p" then open = false break end
            end
            if open then bonus = bonus + 1.2 end
        end
    elseif style == "prudent" then
        if m.castle then bonus = bonus + 3.5 end
        local diff = pos:material(us) - pos:material(them)
        if m.captured and diff >= 2 then bonus = bonus + 2 end -- simplifier quand on mène
        if gives_check then bonus = bonus - 0.5 end
        local mk = pos:kingSquare(us)
        if l == "p" and mk and math.abs(Chess.fileOf(m.from) - Chess.fileOf(mk)) <= 1
            and not opening then
            bonus = bonus - 1.5 -- ne pas affaiblir le roi
        end
        if l == "k" and not m.castle and opening then bonus = bonus - 1 end
        -- pièce déplacée encore attaquée ? on n'aime pas
        if after:isAttacked(m.to, them) and not after:isAttacked(m.to, us) then bonus = bonus - 1.5 end
    elseif style == "piegeur" then
        if attacked_value >= 5 then bonus = bonus + 2.5 end
        if gives_check then bonus = bonus + 1.5 end
        -- un coup « pas évident » : ni prise ni développement banal
        if not m.captured and l ~= "p" and not m.castle then bonus = bonus + 0.5 end
        -- double attaque
        local count = 0
        for _, s in ipairs(after:attacksFrom(m.to)) do
            local p = after.board[s]
            if p and Chess.colorOf(p) == them and (Chess.VALUES[p:lower()] >= 3 or p:lower() == "k") then
                count = count + 1
            end
        end
        if count >= 2 then bonus = bonus + 2 end
    end
    return bonus
end

--[[
  Choisit un coup.
  pos : position (l'IA est au trait)
  lines : analyse Stockfish (MultiPV) de cette position
  rnd : fonction aléatoire (math.random par défaut)
  Renvoie : coup (table de Chess), uci
]]
function AI.chooseMove(pos, lines, elo, style, rnd)
    rnd = rnd or math.random
    local legal = pos:legalMoves()
    if #legal == 0 then return nil end
    if #legal == 1 then return legal[1], Chess.moveToUci(legal[1]) end

    -- Bévue occasionnelle : un coup au hasard (mais jamais quand un mat est à portée)
    local best = lines[1]
    local hasMate = best and best.mate and best.mate > 0
    if not hasMate and rnd() < blunderChance(elo) then
        -- les débutants jouent souvent des coups « naturels » : on pondère par le style
        local weights, total = {}, 0
        for i, m in ipairs(legal) do
            local w = 1 + math.max(0, AI.styleBonus(style, pos, m)) * 0.5
            if m.captured then w = w + 1 end
            weights[i] = w
            total = total + w
        end
        local r = rnd() * total
        for i, m in ipairs(legal) do
            r = r - weights[i]
            if r <= 0 then return m, Chess.moveToUci(m) end
        end
        return legal[#legal], Chess.moveToUci(legal[#legal])
    end

    if not best then
        local m = legal[math.floor(rnd() * #legal) + 1]
        return m, Chess.moveToUci(m)
    end

    local T = temperature(elo)
    local style_scale = 0.4 + 0.6 * math.min(1, T / 5)
    local bestWin = AI.winPercent(best.cp)
    local cands = {}
    for _, line in ipairs(lines) do
        local m = pos:findUci(line.move)
        if m then
            local loss = bestWin - AI.winPercent(line.cp)
            -- ne jamais rater un mat forcé à haut niveau
            if hasMate and elo >= 1500 and not (line.mate and line.mate > 0) then loss = loss + 50 end
            local score = -loss + AI.styleBonus(style, pos, m) * style_scale
            cands[#cands + 1] = { m = m, score = score }
        end
    end
    if #cands == 0 then
        local m = pos:findUci(best.move) or legal[1]
        return m, Chess.moveToUci(m)
    end
    local maxs = -math.huge
    for _, c in ipairs(cands) do if c.score > maxs then maxs = c.score end end
    local total = 0
    for _, c in ipairs(cands) do
        c.w = math.exp((c.score - maxs) / T)
        total = total + c.w
    end
    local r = rnd() * total
    for _, c in ipairs(cands) do
        r = r - c.w
        if r <= 0 then return c.m, Chess.moveToUci(c.m) end
    end
    return cands[1].m, Chess.moveToUci(cands[1].m)
end

-- Nouveau classement du joueur après une partie (formule Elo classique)
function AI.updateRating(player, opponent, score, games_played)
    local k = (games_played or 0) < 10 and 40 or (player >= 2000 and 16 or 24)
    local expected = 1 / (1 + 10 ^ ((opponent - player) / 400))
    local new = player + k * (score - expected)
    return math.floor(new + 0.5)
end

---------------------------------------------------------------------------
-- Personnalités des joueurs humains simulés (tournois, parties libres)
---------------------------------------------------------------------------

--[[
  speed    : multiplicateur du temps de réflexion (petit = joue vite)
  strength : bonus/malus d'Elo réel en partie
  stress   : sensibilité au manque de temps
  draw     : goût pour la nulle (0..1)
  resign   : seuil d'abandon (en centipions de retard)
]]
AI.PERSONAS = {
    attaquant = { name = "Attaquant", style = "attaquant", speed = 0.6, strength = -60, stress = 1.2,
        draw = 0.10, resign = 1200,
        desc = "Joue vite et cherche l'attaque à tout prix, quitte à se découvrir." },
    positionnel = { name = "Positionnel", style = "stratege", speed = 1.1, strength = 20, stress = 0.9,
        draw = 0.35, resign = 800,
        desc = "Calme et méthodique : améliore ses pièces petit à petit." },
    solide = { name = "Solide", style = "prudent", speed = 1.2, strength = 30, stress = 0.8,
        draw = 0.55, resign = 900,
        desc = "Très difficile à battre, aime les positions sûres et accepte volontiers la nulle." },
    tacticien = { name = "Tacticien", style = "piegeur", speed = 0.9, strength = 0, stress = 1.0,
        draw = 0.20, resign = 1000,
        desc = "Voit les combinaisons et adore tendre des pièges." },
    zeitnot = { name = "Grand réfléchisseur", style = "equilibre", speed = 1.7, late_speed = 0.55,
        strength = 40, stress = 1.6, draw = 0.25, resign = 1000,
        desc = "Réfléchit très longtemps en début de partie… et se retrouve souvent à court de temps." },
    blitzeur = { name = "Blitzeur", style = "equilibre", speed = 0.35, strength = -40, stress = 0.6,
        draw = 0.20, resign = 1100,
        desc = "Joue presque instantanément, à l'instinct. Redoutable quand la pendule tourne." },
    equilibre = { name = "Équilibré", style = "equilibre", speed = 1.0, strength = 0, stress = 1.0,
        draw = 0.30, resign = 900,
        desc = "Un joueur complet, sans point faible marqué." },
}
AI.PERSONA_IDS = { "attaquant", "positionnel", "solide", "tacticien", "zeitnot", "blitzeur", "equilibre" }

function AI.persona(id)
    return AI.PERSONAS[id] or AI.PERSONAS.equilibre
end

-- Cadences
AI.CADENCES = {
    blitz = { id = "blitz", name = "Blitz 3 + 5", base = 180, inc = 5, factor = 0.60 },
    rapide = { id = "rapide", name = "Rapide 10 + 5", base = 600, inc = 5, factor = 0.73 },
    long = { id = "long", name = "Rapide 15 + 10", base = 900, inc = 10, factor = 0.82 },
}

function AI.cadenceFactor(tc)
    if not tc then return 1 end
    for _, c in pairs(AI.CADENCES) do
        if c.base == tc.base and c.inc == tc.inc then return c.factor end
    end
    -- interpolation sur le temps total estimé (40 coups)
    local total = tc.base + 40 * (tc.inc or 0)
    if total >= 3600 then return 1 end
    return math.max(0.55, math.min(1, 0.55 + 0.45 * (total - 180) / 3400))
end

--[[
  Niveau réellement joué à ce coup.
  elo : classement affiché ; tc : cadence (nil = sans pendule)
  remaining : temps restant (s) ; persona : table de personnalité
  rushed : rapport temps pris / temps « normal » (<1 = coup joué vite)
]]
function AI.effectiveElo(elo, tc, persona, remaining, rushed)
    persona = persona or AI.PERSONAS.equilibre
    local e = elo + (persona.strength or 0)
    if tc then
        e = 400 + (e - 400) * AI.cadenceFactor(tc)
        -- stress de la pendule
        local ref = math.max(45, tc.base * 0.15)
        if remaining and remaining < ref then
            local stress = (ref - remaining) / ref
            e = e - stress * 320 * (persona.stress or 1)
        end
        if rushed and rushed < 1 then
            e = e - (1 - rushed) * 120
        end
    end
    return math.max(150, math.floor(e))
end

local function lognormal(rnd, sigma)
    -- Box-Muller
    local u1 = math.max(1e-6, rnd())
    local u2 = rnd()
    local z = math.sqrt(-2 * math.log(u1)) * math.cos(2 * math.pi * u2)
    return math.exp(z * sigma)
end

--[[
  Temps de réflexion « humain » (en secondes) pour un coup.
  ctx = { persona, remaining, opp_remaining, tc, fullmove, nlegal,
          lines (analyse MultiPV), recapture (bool), opp_last_think, rnd }
  Renvoie : secondes, et le temps « normal » de référence
]]
function AI.humanThinkTime(ctx)
    local rnd = ctx.rnd or math.random
    local p = ctx.persona or AI.PERSONAS.equilibre
    local tc = ctx.tc
    local remaining = ctx.remaining
    local inc = tc.inc or 0
    local movesLeft = math.max(18, 42 - (ctx.fullmove or 1) * 0.55)
    local budget = remaining / movesLeft + inc * 0.85

    local factor = 1
    local fm = ctx.fullmove or 1
    if fm <= 5 then factor = 0.22
    elseif fm <= 9 then factor = 0.55 end

    local lines = ctx.lines or {}
    if ctx.nlegal == 1 then
        factor = 0.08
    elseif lines[1] and lines[2] then
        local gap = math.abs((lines[1].cp or 0) - (lines[2].cp or 0))
        if gap > 250 then
            factor = factor * 0.45           -- coup évident
        else
            local close = 0
            for i = 2, #lines do
                if math.abs((lines[1].cp or 0) - (lines[i].cp or 0)) < 40 then close = close + 1 end
            end
            if close >= 2 and fm > 9 then factor = factor * 1.5 end -- position complexe
        end
        if lines[1].mate then factor = factor * 0.6 end
    end
    if ctx.recapture then factor = factor * 0.4 end

    local speed = p.speed or 1
    if p.late_speed and fm > 24 then speed = p.late_speed end
    -- l'adversaire a longuement réfléchi : on a pu réfléchir pendant ce temps
    if ctx.opp_last_think and ctx.opp_last_think > budget * 2 then factor = factor * 0.75 end
    -- en avance à la pendule, on se permet un peu plus de temps
    if ctx.opp_remaining and remaining > ctx.opp_remaining * 1.8 and remaining > 60 then
        factor = factor * 1.15
    end

    local t = budget * factor * speed * lognormal(rnd, 0.45)
    local reaction = 0.8 + rnd() * 0.9
    if ctx.recapture or ctx.nlegal == 1 then reaction = 0.5 + rnd() * 0.5 end
    t = math.max(t, reaction)
    -- jamais plus d'un quart du temps restant, et garder une marge
    t = math.min(t, remaining * 0.25 + inc * 0.5, math.max(0.4, remaining - 1.5))
    if remaining < 20 then t = math.min(t, 1.2 + rnd() * 1.5) end
    return t, budget
end

-- Le moteur accepte-t-il une proposition de nulle ?
-- ai_cp : évaluation du point de vue de l'IA ; ratio_time : temps IA / temps joueur
function AI.acceptsDraw(persona, ai_cp, fullmove, ratio_time, rnd)
    rnd = rnd or math.random
    persona = persona or AI.PERSONAS.equilibre
    if ai_cp == nil then return false end
    if ai_cp < -150 then return true end
    if fullmove < 20 then return false end
    if ai_cp > 120 then return false end
    local chance = persona.draw or 0.3
    if math.abs(ai_cp) <= 40 then chance = chance + 0.25 end
    if ratio_time and ratio_time < 0.35 then chance = chance + 0.3 end
    return rnd() < chance
end

return AI
