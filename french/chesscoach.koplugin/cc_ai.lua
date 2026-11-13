--[[
  Choix du coup de l'IA : niveau (Elo 400 à 2500) et style de jeu.

  Version « humaine » (calibrée sur ~7 800 parties Lichess blitz et rapide) :
  - Stockfish analyse la position et propose plusieurs coups ;
  - on tire la taille de l'erreur qu'un humain de ce niveau ferait ici, d'après
    les vraies parties (selon le niveau, la cadence, la phase de jeu, la pendule,
    une recapture évidente, un cadeau de l'adversaire, une gaffe juste avant…) ;
  - puis on choisit, parmi les coups dont la perte est proche, celui qu'un humain
    jouerait le plus volontiers (prises, échecs, développement, pièce attaquée…),
    et pour les grosses gaffes : une pièce laissée en prise ou une tactique cachée,
    dans les proportions observées à ce niveau ;
  - en début de partie, les coups viennent souvent du « livre humain » : les coups
    réellement joués par les joueurs de ce niveau sur Lichess.
  Niveau : Elo affiché + 175 (demande du joueur, réglé par matchs simulés contre l'ancienne IA).
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

local Human = require("cc_human")
local BOOK -- chargé à la demande

-- Repères des tranches de niveau (centre de chaque tranche des données Lichess)
local CENTERS = Human.centers

local function clamp(x, a, b) if x < a then return a elseif x > b then return b end return x end

-- Indices de tranche voisins et poids pour interpoler selon l'Elo
local function bandBlend(elo)
    local n = #CENTERS
    if elo <= CENTERS[1] then return 1, 1, 0 end
    if elo >= CENTERS[n] then return n, n, 0 end
    for i = 1, n - 1 do
        if elo <= CENTERS[i + 1] then
            return i, i + 1, (elo - CENTERS[i]) / (CENTERS[i + 1] - CENTERS[i])
        end
    end
    return n, n, 0
end

local function bandOf(elo)
    local i, j, t = bandBlend(elo)
    return t < 0.5 and i or j
end
AI.bandOf = bandOf

-- Interpole une valeur numérique tabulée par tranche
local function lerpBand(tbl, elo)
    local i, j, t = bandBlend(elo)
    local a, b = tbl[i], tbl[j]
    if a == nil then return b end
    if b == nil then return a end
    return a + (b - a) * t
end

-- Cadence « blitz » ou « rapide » (sans pendule : comme en rapide)
function AI.speedOf(tc)
    if not tc then return "rapid" end
    if tc.base + 40 * (tc.inc or 0) < 480 then return "blitz" end
    return "rapid"
end

local function phaseOf(fullmove)
    if fullmove <= 10 then return 1 elseif fullmove <= 30 then return 2 end
    return 3
end

-- Au-delà des tranches mesurées : on augmente / diminue la masse d'erreurs
local function extrapolation(elo)
    local lo, hi = CENTERS[1], CENTERS[#CENTERS]
    if elo < lo then return 1 + (lo - elo) / 450 * 0.9 end      -- 400 Elo : erreurs ×1,9
    if elo > hi then return math.max(0.25, 1 - (elo - hi) / 400 * 0.6) end -- 2750 : ×0,4
    return 1
end

-- Distribution des pertes (en points de % de gain) pour ce niveau / cette phase
local function lossDistribution(elo, speed, phase)
    local i, j, t = bandBlend(elo)
    local da = Human.dist[speed][i][phase]
    local db = Human.dist[speed][j][phase]
    local d = {}
    for k = 1, #da do d[k] = da[k] + (db[k] - da[k]) * t end
    return d
end

-- Index du premier intervalle considéré comme une « erreur » (perte ≥ 7 %)
local ERR_BIN
for k, e in ipairs(Human.edges) do if e >= 7 and not ERR_BIN then ERR_BIN = k end end

--[[
  Tire la perte (0..100) qu'un humain de ce niveau ferait sur ce coup.
  factor : multiplie la probabilité de faire une erreur (pendule, recapture…)
]]
function AI.sampleLoss(elo, speed, phase, factor, rnd)
    rnd = rnd or math.random
    local d = lossDistribution(elo, speed, phase)
    factor = (factor or 1) * extrapolation(elo) * AI.ERROR_SCALE
        * (AI.STEEPNESS ^ ((elo - 1300) / 200))
    local errMass = 0
    for k = ERR_BIN, #d do errMass = errMass + d[k] end
    if errMass > 0 and factor ~= 1 then
        local new = clamp(errMass * factor, 0.002, 0.85)
        local up, down = new / errMass, (1 - new) / (1 - errMass)
        for k = 1, #d do d[k] = d[k] * (k >= ERR_BIN and up or down) end
    end
    local r = rnd()
    local e = Human.edges
    for k = 1, #d do
        r = r - d[k]
        if r <= 0 then return e[k] + (e[k + 1] - e[k]) * rnd() end
    end
    return 0
end

-- Facteur sur la probabilité d'erreur selon la situation (données Lichess)
function AI.errorFactor(elo, speed, ctx)
    ctx = ctx or {}
    local b = bandOf(elo)
    local f = 1
    if ctx.clock_bucket then
        f = f * (Human.clock[speed][b][ctx.clock_bucket + 1] or 1)
    end
    if ctx.punish then
        f = f * (Human.sit[speed][b].punir or 1)
    elseif ctx.recapture or ctx.obvious then
        f = f * (Human.sit[speed][b].recapture or 1)
    else
        f = f * (Human.sit[speed][b].normal or 1)
    end
    if ctx.tilt and ctx.tilt > 0 then
        -- après une gaffe, on gaffe plus souvent (effet atténué avec le temps)
        f = f * (1 + (Human.tilt_factor - 1) * ctx.tilt)
    end
    if ctx.rushed then f = f * ctx.rushed end
    -- les effets ne s'additionnent pas sans fin (les données mesurent chaque effet séparément)
    return clamp(f, 0.35, 2.4)
end

-- Temps de réflexion conseillé (ms) pour l'analyse de Stockfish (mode coach)
function AI.thinkTime(elo, base)
    base = base or 1000
    if elo >= 2200 then return base * 1.5 end
    if elo >= 1600 then return base end
    return math.max(500, base * 0.8)
end

-- Nombre de coups candidats à demander à Stockfish (plus de choix = erreurs plus variées)
function AI.multiPV(elo)
    return 10 -- le modèle humain a été entraîné sur les 10 meilleurs coups de Stockfish
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

---------------------------------------------------------------------------
-- Ce qu'un humain « voit » : pièce laissée en prise après un coup
---------------------------------------------------------------------------

local function pval(p) return p and Chess.VALUES[p:lower()] or 0 end

-- Plus gros gain matériel immédiat pour l'adversaire (une prise, échange simple)
local function hangValue(after, us)
    local them = Chess.other(us)
    local worst = 0
    for sq = 0, 63 do
        local p = after.board[sq]
        if p and Chess.colorOf(p) == us and p:lower() ~= "k" then
            local atk = after:attackersOf(sq, them)
            if #atk > 0 then
                local v = pval(p)
                local cheapest = 99
                for _, a in ipairs(atk) do
                    local av = pval(after.board[a])
                    if av == 0 then av = 50 end -- le roi ne prend que si la case n'est pas défendue
                    if av < cheapest then cheapest = av end
                end
                local defended = after:isAttacked(sq, us)
                local gain
                if not defended then gain = (cheapest == 50 and v or v)
                elseif cheapest == 50 then gain = 0
                else gain = v - cheapest end
                if gain > worst then worst = gain end
            end
        end
    end
    return worst
end
AI.hangValue = hangValue

-- Le coup est-il « naturel » pour un humain ? (multiplicateur de préférence)
local function naturalness(pos, m, after, elo, style, ctx)
    local w = 1
    local l = m.piece:lower()
    local fm = pos.fullmove
    local us = pos.turn
    if m.captured then w = w * 1.5 end
    if after:inCheck() then w = w * (elo < 1200 and 1.8 or 1.3) end
    if ctx and ctx.last_to and m.to == ctx.last_to and m.captured then w = w * 2.0 end -- recapture
    -- pièce attaquée qu'on met à l'abri
    if pos:isAttacked(m.from, Chess.other(us)) and l ~= "p" then w = w * 1.4 end
    if fm <= 12 then
        local back = us == "w" and 0 or 7
        if (l == "n" or l == "b") and Chess.rankOf(m.from) == back then w = w * 1.5 end
        if m.castle then w = w * 1.6 end
        if l == "q" and fm <= 6 then w = w * (elo < 1000 and 1.3 or 0.6) end
        if l == "k" and not m.castle then w = w * 0.3 end
        if l == "p" and (Chess.fileOf(m.from) == 0 or Chess.fileOf(m.from) == 7) and elo >= 1200 then w = w * 0.6 end
    elseif l == "k" and not m.castle and pos:material(us) + pos:material(Chess.other(us)) > 30 then
        w = w * 0.5
    end
    local bonus = AI.styleBonus(style, pos, m)
    if bonus ~= 0 then w = w * math.exp(clamp(bonus, -4, 4) * 0.18) end
    return w
end

local function bookMove(pos, elo, rnd)
    if not BOOK then
        local ok, b = pcall(require, "cc_book")
        BOOK = ok and b or false
    end
    if not BOOK then return nil end
    local band = BOOK[bandOf(elo)]
    local entry = band and band[pos:key()]
    if not entry then return nil end
    local cands, total = {}, 0
    for u, n in entry:gmatch("(%S+):(%d+)") do
        local w = tonumber(n) ^ 0.9
        cands[#cands + 1] = { u = u, w = w }
        total = total + w
    end
    if total <= 0 then return nil end
    local r = rnd() * total
    for _, c in ipairs(cands) do
        r = r - c.w
        if r <= 0 then return pos:findUci(c.u) end
    end
    return nil
end

--[[
  Choisit un coup.
  pos : position (l'IA est au trait)
  lines : analyse Stockfish (MultiPV) de cette position
  elo : niveau réellement joué (après forme du jour, personnalité…)
  rnd : fonction aléatoire (math.random par défaut)
  ctx (facultatif) : { speed, clock_bucket, last_to, recapture, punish, tilt, rushed, book }
  Renvoie : coup (table de Chess), uci, infos { loss = perte visée, kind = "livre"|"humain"|… }
]]
function AI.chooseMoveHuman(pos, lines, elo, style, rnd, ctx)
    rnd = rnd or math.random
    ctx = ctx or {}
    local legal = pos:legalMoves()
    if #legal == 0 then return nil end
    if #legal == 1 then return legal[1], Chess.moveToUci(legal[1]), { kind = "seul" } end
    local speed = ctx.speed or "rapid"
    local best = lines[1]

    -- 1) le livre humain (début de partie)
    if ctx.book ~= false and pos.fullmove <= 8 and rnd() < 0.93 then
        local m = bookMove(pos, elo, rnd)
        if m then return m, Chess.moveToUci(m), { kind = "livre" } end
    end
    if not best then
        local m = legal[math.floor(rnd() * #legal) + 1]
        return m, Chess.moveToUci(m), { kind = "hasard" }
    end

    -- 2) un mat en 1 se voit presque toujours
    if best.mate and best.mate == 1 then
        local see = elo < 800 and 0.85 or (elo < 1200 and 0.95 or 0.995)
        if rnd() < see then
            local m = pos:findUci(best.move)
            if m then return m, best.move, { kind = "mat" } end
        end
    end

    -- 3) la perte que ferait un humain de ce niveau ici
    --    (un cadeau évident — une pièce à prendre gratuitement — se voit presque toujours ;
    --     c'est le cadeau caché, tactique, que l'on rate souvent)
    local bm = pos:findUci(best.move)
    if bm and bm.captured then
        local v = pval(bm.captured)
        local defended = pos:makeMove(bm):isAttacked(bm.to, Chess.other(pos.turn))
        if v >= 3 and (not defended or v > pval(bm.piece)) then
            ctx = setmetatable({ punish = false, obvious = true }, { __index = ctx })
        end
    end
    local factor = AI.errorFactor(elo, speed, ctx)
    local target = AI.sampleLoss(elo, speed, phaseOf(pos.fullmove), factor, rnd)

    -- 4) pertes de chaque coup : celles de Stockfish, et une estimation pour les autres
    local bestWin = AI.winPercent(best.cp)
    local worstCp = best.cp
    local known = {}
    for _, line in ipairs(lines) do
        if line.move then known[line.move] = line.cp end
        if line.cp < worstCp then worstCp = line.cp end
    end
    local us = pos.turn
    local cands = {}
    for _, m in ipairs(legal) do
        local u = Chess.moveToUci(m)
        local after = pos:makeMove(m)
        local hang = hangValue(after, us)
        local cap = pval(m.captured) + (m.promo and (pval(m.promo) - 1) or 0)
        local cp = known[u]
        local estimated = cp == nil
        if estimated then
            local net = math.max(0, hang - cap)
            cp = math.min(worstCp - 35, best.cp - 100 * net)
        end
        local loss = math.max(0, bestWin - AI.winPercent(cp))
        cands[#cands + 1] = {
            m = m, u = u, loss = loss, after = after,
            visible = hang - cap >= 2,  -- pièce laissée en prise (gaffe « visible »)
            hang = hang,
        }
    end

    -- 5) grosses gaffes : pièce en prise ou tactique cachée, selon les proportions observées
    local pool = cands
    if target >= 15 then
        local vis = lerpBand(Human.visible, elo)
        local wantVisible = rnd() < vis
        local sub = {}
        for _, c in ipairs(cands) do
            if c.loss >= 8 and c.visible == wantVisible then sub[#sub + 1] = c end
        end
        if #sub > 0 then pool = sub end
    end

    -- 6) choisir le coup dont la perte est proche, en préférant les coups naturels
    local tau = 1.5 + 0.25 * target
    local total = 0
    for _, c in ipairs(pool) do
        local wgt = math.exp(-math.abs(c.loss - target) / tau) * naturalness(pos, c.m, c.after, elo, style, ctx)
        -- on surveille sa dame et ses tours : on les laisse moins souvent en prise qu'un pion ou un cavalier
        if c.visible and c.hang >= 9 then wgt = wgt * (elo < 900 and 0.6 or 0.25)
        elseif c.visible and c.hang >= 5 then wgt = wgt * (elo < 900 and 0.8 or 0.5) end
        c.w = wgt
        total = total + wgt
    end
    local pick = pool[1]
    if total > 0 then
        local r = rnd() * total
        for _, c in ipairs(pool) do
            r = r - c.w
            if r <= 0 then pick = c break end
        end
    end
    return pick.m, pick.u, { kind = "humain", target = target, loss = pick.loss }
end

-- Tolérance aux coups imparfaits selon le niveau (comme la première version, qui jouait bien)
local function temperature(elo)
    local t = (elo - AI.MIN_ELO) / (AI.MAX_ELO - AI.MIN_ELO)
    t = clamp(t, 0, 1)
    return 25 * (0.02 ^ t)
end

-- Fréquence des vraies gaffes (perte ≥ 20 %) mesurée sur Lichess pour ce niveau
local function lichessBlunderRate(elo, speed, phase)
    local d = lossDistribution(elo, speed, phase)
    local r = 0
    for k, e in ipairs(Human.edges) do
        if e >= 20 and d[k] then r = r + d[k] end
    end
    return r * extrapolation(elo)
end
AI.lichessBlunderRate = lichessBlunderRate

-- Part des gaffes humaines gardées : l'IA joue sinon comme Stockfish « bridé »,
-- et ne garde que les oublis tactiques crédibles (pas de pion donné au hasard)
AI.OVERSIGHT_SHARE = 0.45

--[[
  Choisit un coup.
  Stockfish d'abord : on choisit parmi ses meilleurs coups, avec une tolérance
  qui dépend du niveau. De temps en temps (fréquence mesurée sur Lichess pour ce
  niveau, plus en zeitnot, après une gaffe…), un oubli tactique « humain » :
  un coup que Stockfish a considéré, qui a l'air correct mais qui est réfuté par
  une tactique — jamais une pièce ou un pion laissé en prise au hasard.
  ctx (facultatif) : { speed, clock_bucket, last_to, recapture, punish, tilt, book }
  Renvoie : coup, uci, infos { kind, loss }
]]
function AI.chooseMoveClassic(pos, lines, elo, style, rnd, ctx)
    rnd = rnd or math.random
    ctx = ctx or {}
    local legal = pos:legalMoves()
    if #legal == 0 then return nil end
    if #legal == 1 then return legal[1], Chess.moveToUci(legal[1]), { kind = "seul", loss = 0 } end
    local speed = ctx.speed or "rapid"
    local best = lines[1]

    -- 1) le livre humain (début de partie, coups vérifiés par Stockfish)
    if ctx.book ~= false and pos.fullmove <= 8 and rnd() < 0.85 then
        local m = bookMove(pos, elo, rnd)
        if m then
            local u = Chess.moveToUci(m)
            local ok = true
            if best then
                -- le livre ne doit pas proposer un coup que Stockfish juge mauvais ici
                local cp
                for _, l in ipairs(lines) do if l.move == u then cp = l.cp end end
                if cp == nil or AI.winPercent(best.cp) - AI.winPercent(cp) > 6 then ok = false end
            end
            if ok then return m, u, { kind = "livre", loss = 0 } end
        end
    end
    if not best then
        local m = legal[math.floor(rnd() * #legal) + 1]
        return m, Chess.moveToUci(m), { kind = "hasard", loss = 0 }
    end

    -- 2) un mat en 1 se voit presque toujours
    local hasMate = best.mate and best.mate > 0
    if best.mate == 1 and (elo >= 900 or rnd() < 0.9) then
        local m = pos:findUci(best.move)
        if m then return m, best.move, { kind = "mat", loss = 0 } end
    end

    local bestWin = AI.winPercent(best.cp)
    local us = pos.turn
    local cands = {}
    for _, line in ipairs(lines) do
        local m = line.move and pos:findUci(line.move)
        if m then
            local after = pos:makeMove(m)
            local cap = pval(m.captured) + (m.promo and (pval(m.promo) - 1) or 0)
            cands[#cands + 1] = {
                m = m, u = line.move, after = after,
                loss = math.max(0, bestWin - AI.winPercent(line.cp)),
                mate = line.mate and line.mate > 0,
                visible = hangValue(after, us) - cap >= 1,
            }
        end
    end
    if #cands == 0 then
        local m = pos:findUci(best.move) or legal[1]
        return m, Chess.moveToUci(m), { kind = "stockfish", loss = 0 }
    end

    -- 3) oubli tactique « humain » (rare, et seulement quand la partie n'est pas jouée)
    if not hasMate and bestWin > 8 and bestWin < 97 then
        local f = math.min(1.8, AI.errorFactor(elo, speed, ctx))
        local rate = lichessBlunderRate(elo, speed, phaseOf(pos.fullmove)) * AI.OVERSIGHT_SHARE * f
        if rnd() < rate then
            local pool, total = {}, 0
            for _, c in ipairs(cands) do
                -- crédible : Stockfish l'a envisagé, il ne laisse rien en prise au premier coup d'œil
                if c.loss >= 8 and c.loss <= 60 and (not c.visible or elo < 900) then
                    c.w = naturalness(pos, c.m, c.after, elo, style, ctx)
                    pool[#pool + 1] = c
                    total = total + c.w
                end
            end
            if #pool > 0 then
                local r = rnd() * total
                for _, c in ipairs(pool) do
                    r = r - c.w
                    if r <= 0 then return c.m, c.u, { kind = "oubli", loss = c.loss } end
                end
            end
        end
    end

    -- 4) le jeu normal : parmi les meilleurs coups de Stockfish
    local T = temperature(elo)
    local style_scale = 0.4 + 0.6 * math.min(1, T / 5)
    local maxs = -math.huge
    for _, c in ipairs(cands) do
        local loss = c.loss
        -- ne jamais rater un mat forcé à bon niveau
        if hasMate and elo >= 1500 and not c.mate then loss = loss + 50 end
        -- les pions et pièces laissés en prise sans raison : non
        if c.visible and loss > 2 then loss = loss + 6 end
        c.score = -loss + AI.styleBonus(style, pos, c.m) * style_scale
        if c.score > maxs then maxs = c.score end
    end
    local total = 0
    for _, c in ipairs(cands) do
        c.w = math.exp((c.score - maxs) / T)
        total = total + c.w
    end
    local r = rnd() * total
    for _, c in ipairs(cands) do
        r = r - c.w
        if r <= 0 then return c.m, c.u, { kind = "stockfish", loss = c.loss } end
    end
    return cands[1].m, cands[1].u, { kind = "stockfish", loss = cands[1].loss }
end

---------------------------------------------------------------------------
-- Choix du coup : modèle humain appris sur Lichess (cc_model.lua)
---------------------------------------------------------------------------

local Model = require("cc_model")
AI.Model = Model

--[[
  Choisit un coup comme le ferait un humain de ce niveau.
  1) En ouverture : le livre des coups réellement joués à ce niveau (vérifiés par Stockfish).
  2) Ensuite : Stockfish donne ses 10 meilleurs coups ; le modèle appris sur les parties
     Lichess donne à chacun la probabilité qu'un joueur de ce niveau le joue (selon ce qu'il
     coûte et ce qu'un humain voit : prise, échec, recapture, pièce en prise, menace…),
     et le coup est tiré selon ces probabilités.
  elo : niveau Lichess imité (voir AI.effectiveElo)
  ctx (facultatif) : { speed, clock_bucket, last_to, tilt, book }
  Renvoie : coup, uci, infos { kind, loss }
]]
function AI.chooseMove(pos, lines, elo, style, rnd, ctx)
    rnd = rnd or math.random
    ctx = ctx or {}
    if not Model.weights() then return AI.chooseMoveClassic(pos, lines, elo, style, rnd, ctx) end
    local legal = pos:legalMoves()
    if #legal == 0 then return nil end
    if #legal == 1 then return legal[1], Chess.moveToUci(legal[1]), { kind = "seul", loss = 0 } end
    local best = lines[1]

    if ctx.book ~= false and pos.fullmove <= 8 and rnd() < 0.85 then
        local m = bookMove(pos, elo, rnd)
        if m then
            local u = Chess.moveToUci(m)
            local ok = true
            if best then
                local cp
                for _, l in ipairs(lines) do if l.move == u then cp = l.cp end end
                if cp == nil or AI.winPercent(best.cp) - AI.winPercent(cp) > 6 then ok = false end
            end
            if ok then return m, u, { kind = "livre", loss = 0 } end
        end
    end
    if not best then
        local m = legal[math.floor(rnd() * #legal) + 1]
        return m, Chess.moveToUci(m), { kind = "hasard", loss = 0 }
    end

    -- juste après une gaffe, on joue un peu moins bien (mesuré sur Lichess) : niveau abaissé
    local e = elo
    if ctx.tilt and ctx.tilt > 0 then e = e - 120 * ctx.tilt end
    local extra
    if style and style ~= "equilibre" then
        extra = function(p, m) return clamp(AI.styleBonus(style, p, m), -4, 4) * 0.15 end
    end
    local cands = Model.distribution(pos, lines, e, ctx, extra)
    if not cands then return AI.chooseMoveClassic(pos, lines, elo, style, rnd, ctx) end
    local c = Model.sample(cands, rnd)
    return c.m, c.u, { kind = "humain", loss = c.loss, p = c.p }
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
    blitz = { id = "blitz", name = "Blitz 3 + 5", base = 180, inc = 5 },
    rapide = { id = "rapide", name = "Rapide 10 + 5", base = 600, inc = 5 },
    long = { id = "long", name = "Rapide 15 + 10", base = 900, inc = 10 },
}

-- (ancienne version : l'Elo était fortement réduit en blitz ; désormais les données
--  blitz / rapide de Lichess donnent directement le bon niveau pour chaque cadence)
function AI.cadenceFactor() return 1 end

--[[
  Niveau réellement joué à ce coup.
  elo : classement affiché ; tc : cadence (nil = sans pendule)
  remaining : temps restant (s) ; persona : table de personnalité
  form : forme du jour (Elo, tiré au début de la partie)
]]
-- L'Elo affiché suit l'échelle de chess.com ; le modèle est appris sur Lichess, où les
-- classements sont plus hauts (environ +375 à 1000, +260 à 1500, +150 à 2000, 0 vers 2650).
function AI.lichessGap(elo)
    return clamp(375 - (elo - 1000) * 0.225, 0, 400)
end
AI.STRENGTH_OFFSET = 0

function AI.effectiveElo(elo, tc, persona, remaining, rushed, form)
    persona = persona or AI.PERSONAS.equilibre
    local e = elo + AI.lichessGap(elo) + AI.STRENGTH_OFFSET + (persona.strength or 0) + (form or 0)
    return math.max(150, math.floor(e))
end

-- Tranche de pendule (0 : plus de la moitié du temps … 3 : zeitnot) comme dans les données
function AI.clockBucket(tc, remaining)
    if not tc or not remaining then return nil end
    local f = remaining / tc.base
    if remaining < 15 or f < 0.1 then return 3 end
    if f < 0.2 then return 2 end
    if f < 0.5 then return 1 end
    return 0
end

-- Forme du jour d'un joueur : quelques dizaines d'Elo en plus ou en moins
function AI.dailyForm(rnd)
    rnd = rnd or math.random
    local u1 = math.max(1e-6, rnd())
    local z = math.sqrt(-2 * math.log(u1)) * math.cos(2 * math.pi * rnd())
    return math.floor(clamp(z * 45, -110, 110))
end

local function lognormal(rnd, sigma)
    -- Box-Muller
    local u1 = math.max(1e-6, rnd())
    local u2 = rnd()
    local z = math.sqrt(-2 * math.log(u1)) * math.cos(2 * math.pi * u2)
    return math.exp(z * sigma)
end

local function moveBucket(fm)
    for i, b in ipairs(Human.move_buckets) do
        if fm >= b[1] and fm <= b[2] then return i end
    end
    return #Human.move_buckets
end

--[[
  Temps de réflexion « humain » (en secondes) pour un coup, calibré sur Lichess :
  part du temps restant utilisée selon le numéro du coup et le niveau, très variable
  d'un coup à l'autre (coups joués d'instinct, longues réflexions), quelques secondes
  par coup en zeitnot.
  ctx = { persona, remaining, opp_remaining, tc, fullmove, nlegal, elo,
          lines (analyse MultiPV), recapture (bool), opp_last_think, rnd }
  Renvoie : secondes, et le temps « normal » de référence
]]
function AI.humanThinkTime(ctx)
    local rnd = ctx.rnd or math.random
    local p = ctx.persona or AI.PERSONAS.equilibre
    local tc = ctx.tc
    local remaining = ctx.remaining
    local inc = tc.inc or 0
    local speed = AI.speedOf(tc)
    local elo = ctx.elo or 1500
    local fm = ctx.fullmove or 1
    local i, j, t = bandBlend(elo)
    local mb = moveBucket(fm)
    local ra = Human.time[speed][i][mb]
    local rb = Human.time[speed][j][mb]
    local ratio = ra + (rb - ra) * t
    -- en ouverture on joue vite même avec un incrément (coups connus)
    local budget = remaining * ratio + inc * 0.8 * clamp((fm - 4) / 10, 0.1, 1)

    local factor = 1
    local lines = ctx.lines or {}
    if ctx.nlegal == 1 then
        factor = 0.08
    elseif lines[1] and lines[2] then
        local gap = math.abs((lines[1].cp or 0) - (lines[2].cp or 0))
        if gap > 250 then
            factor = factor * 0.5           -- coup évident
        else
            local close = 0
            for k = 2, #lines do
                if math.abs((lines[1].cp or 0) - (lines[k].cp or 0)) < 40 then close = close + 1 end
            end
            if close >= 2 and fm > 9 then factor = factor * 1.4 end -- position complexe
        end
        if lines[1].mate then factor = factor * 0.6 end
    end
    if ctx.recapture then factor = factor * 0.35 end

    local speedp = p.speed or 1
    if p.late_speed and fm > 24 then speedp = p.late_speed end
    -- l'adversaire a longuement réfléchi : on a pu réfléchir pendant ce temps
    if ctx.opp_last_think and ctx.opp_last_think > budget * 3 then factor = factor * 0.8 end
    -- en avance à la pendule, on se permet un peu plus de temps
    if ctx.opp_remaining and remaining > ctx.opp_remaining * 1.8 and remaining > 60 then
        factor = factor * 1.15
    end

    local tt
    local zeit = remaining < 15 or remaining < tc.base * 0.1
    if zeit then
        local trouble = lerpBand(Human.trouble[speed], elo)
        tt = trouble * lognormal(rnd, 0.55) * (speedp < 1 and 0.85 or 1)
        if ctx.recapture or ctx.nlegal == 1 then tt = tt * 0.5 end
    else
        tt = budget * factor * speedp * lognormal(rnd, Human.sdlog * (fm <= 8 and 0.6 or 0.8))
        if fm <= 3 then tt = math.min(tt, tc.base * 0.03 + 1) end
    end
    local reaction = 0.7 + rnd() * 0.9
    if ctx.recapture or ctx.nlegal == 1 then reaction = 0.4 + rnd() * 0.5 end
    tt = math.max(tt, reaction)
    -- jamais plus d'un quart du temps restant, et garder une marge
    tt = math.min(tt, remaining * 0.25 + inc * 0.5, math.max(0.4, remaining - 1.5))
    if remaining < 8 then tt = math.min(tt, 0.6 + rnd() * 1.2) end
    return tt, budget
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
