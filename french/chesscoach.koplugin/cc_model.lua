--[[
  Modèle de choix de coup « humain », appris sur de vraies parties Lichess.

  Principe : Stockfish propose ses 10 meilleurs coups avec leur évaluation. Pour chaque
  coup on calcule une trentaine de caractéristiques (ce que le coup coûte, mais aussi ce
  qu'un humain « voit » : prise, échec, recapture, pièce laissée en prise, menace créée,
  développement, recul…). Un modèle statistique (logit conditionnel), entraîné pour chaque
  tranche d'Elo sur les coups réellement joués par des joueurs Lichess de ce niveau dans
  36 000 positions, donne la probabilité qu'un humain de ce niveau joue chaque coup.
  L'IA tire son coup selon ces probabilités.

  Les poids sont dans cc_model_w.lua (fichier généré, ne pas modifier à la main).
]]

local Chess = require("cc_chess")

local Model = {}

Model.MULTIPV = 10

Model.NAMES = {
    "perte_0_2", "perte_2_8", "perte_8_20", "perte_20_50", "perte_50_100",
    "meilleur", "prise", "valeur_prise", "echec", "recapture",
    "en_prise_perdant", "en_prise_correct", "fuite",
    "cavalier", "fou", "tour", "dame", "roi",
    "roque", "promotion", "developpement", "dame_tot", "roi_expose",
    "recul", "distance", "centre", "pion_double", "pion_avance",
    "menace", "mat_gagnant", "mat_en_1", "zeitnot_perte", "peu_de_temps_perte",
}
Model.N = #Model.NAMES

local function clamp(x, a, b) if x < a then return a elseif x > b then return b end return x end
local function pval(p) return p and Chess.VALUES[p:lower()] or 0 end

function Model.winPercent(cp)
    cp = clamp(cp, -10000, 10000)
    if cp > 9000 then return 100 end
    if cp < -9000 then return 0 end
    return 50 + 50 * (2 / (1 + math.exp(-0.00368208 * cp)) - 1)
end

-- Plus gros gain matériel immédiat pour l'adversaire (une prise, échange simple)
function Model.hangValue(after, us)
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
                    if av == 0 then av = 50 end
                    if av < cheapest then cheapest = av end
                end
                local defended = after:isAttacked(sq, us)
                local gain
                if not defended then gain = v
                elseif cheapest == 50 then gain = 0
                else gain = v - cheapest end
                if gain > worst then worst = gain end
            end
        end
    end
    return worst
end

--[[
  Caractéristiques d'un coup candidat.
  pos : position avant le coup ; m : coup ; after : position après ;
  loss : perte en points de % de gain par rapport au meilleur coup ; rank : rang Stockfish ;
  mate : nombre de coups avant mat annoncé par Stockfish (ou nil) ;
  ctx : { last_to = case d'arrivée du dernier coup adverse, clock_bucket = 0..3 }
]]
function Model.features(pos, m, after, loss, rank, mate, ctx)
    local f = {}
    local us = pos.turn
    local them = Chess.other(us)
    local l = m.piece:lower()
    local fm = pos.fullmove
    f[1] = math.min(loss, 2) / 2
    f[2] = clamp(loss - 2, 0, 6) / 6
    f[3] = clamp(loss - 8, 0, 12) / 12
    f[4] = clamp(loss - 20, 0, 30) / 30
    f[5] = clamp(loss - 50, 0, 50) / 50
    f[6] = rank == 1 and 1 or 0
    local capv = pval(m.captured)
    f[7] = m.captured and 1 or 0
    f[8] = capv / 9
    f[9] = after:inCheck() and 1 or 0
    f[10] = (m.captured and ctx and ctx.last_to == m.to) and 1 or 0
    local cap = capv + (m.promo and (pval(m.promo) - 1) or 0)
    local h = clamp(Model.hangValue(after, us) - cap, 0, 9) / 9
    f[11] = loss >= 8 and h or 0
    f[12] = loss < 8 and h or 0
    f[13] = (l ~= "p" and l ~= "k" and pos:isAttacked(m.from, them)) and 1 or 0
    f[14] = l == "n" and 1 or 0
    f[15] = l == "b" and 1 or 0
    f[16] = l == "r" and 1 or 0
    f[17] = l == "q" and 1 or 0
    f[18] = l == "k" and 1 or 0
    f[19] = m.castle and 1 or 0
    f[20] = m.promo and 1 or 0
    local fr, tr = Chess.rankOf(m.from), Chess.rankOf(m.to)
    if us == "b" then fr, tr = 7 - fr, 7 - tr end
    f[21] = (fm <= 12 and (l == "n" or l == "b") and fr == 0) and 1 or 0
    f[22] = (fm <= 8 and l == "q") and 1 or 0
    f[23] = (l == "k" and not m.castle and pos:material(us) + pos:material(them) > 30) and 1 or 0
    f[24] = (l ~= "p" and tr < fr) and 1 or 0
    local df = math.abs(Chess.fileOf(m.from) - Chess.fileOf(m.to))
    f[25] = math.max(df, math.abs(fr - tr)) / 7
    local tf = Chess.fileOf(m.to)
    local trr = Chess.rankOf(m.to)
    if (tf == 3 or tf == 4) and (trr == 3 or trr == 4) then f[26] = 1
    elseif tf >= 2 and tf <= 5 and trr >= 2 and trr <= 5 then f[26] = 0.5
    else f[26] = 0 end
    f[27] = (l == "p" and math.abs(tr - fr) == 2) and 1 or 0
    f[28] = (l == "p" and tr >= 5) and 1 or 0
    -- menace créée par la pièce jouée : pièce adverse plus forte, ou non défendue
    local moved = after.board[m.to]
    local mv = pval(moved)
    local threats = 0
    if moved and moved:lower() ~= "k" then
        for sq = 0, 63 do
            local p = after.board[sq]
            if p and Chess.colorOf(p) == them and p:lower() ~= "k" then
                local v = pval(p)
                if v > mv or (v >= 3 and not after:isAttacked(sq, them)) then
                    for _, a in ipairs(after:attackersOf(sq, us)) do
                        if a == m.to then threats = threats + 1 break end
                    end
                end
            end
        end
    end
    f[29] = math.min(threats, 2) / 2
    f[30] = (mate and mate > 0) and 1 or 0
    f[31] = (mate == 1) and 1 or 0
    local cb = ctx and ctx.clock_bucket or 0
    local lc = math.min(loss, 40) / 40
    f[32] = cb == 3 and lc or 0
    f[33] = cb == 2 and lc or 0
    return f
end

local W -- poids, chargés à la demande

local function weights()
    if W == nil then
        local ok, w = pcall(require, "cc_model_w")
        W = ok and w or false
    end
    return W
end
Model.weights = weights
function Model.setWeights(w) W = w end

-- Niveau Lichess visé -> niveau interne du modèle (table de calibrage de cc_model_w.lua).
-- Les humains jouent parfois des coups hors des 10 meilleurs de Stockfish ; le modèle ne
-- choisit que parmi ces 10, donc on vise un peu plus bas pour retrouver la même perte moyenne.
function Model.modelElo(target)
    local w = weights()
    local map = w and w.map
    if not map or #map == 0 then return target end
    -- sous le niveau le plus bas mesuré, on descend vite (réglé par des matchs simulés)
    if target <= map[1][1] then return map[1][2] end
    for k = 1, #map - 1 do
        local a, b = map[k], map[k + 1]
        if target <= b[1] then
            return a[2] + (b[2] - a[2]) * (target - a[1]) / (b[1] - a[1])
        end
    end
    return map[#map][2] + (target - map[#map][1])
end

-- « Netteté » du jeu selon le niveau Lichess visé : à quel point le joueur évite les coups qui
-- perdent. Réglée par des matchs simulés pour que 300 points d'écart se sentent vraiment
-- (le joueur le mieux classé gagne environ 4 parties sur 5).
Model.SHARP_REF = 1607    -- niveau où la netteté vaut 1 (poids appris tels quels)
Model.SHARP_STEP = 300    -- la netteté double tous les 300 points Lichess
function Model.sharpness(target)
    return clamp(2 ^ ((target - Model.SHARP_REF) / Model.SHARP_STEP), 0.08, 16)
end

-- Poids pour un niveau Lichess visé : préférences « humaines » de la tranche d'Elo la plus
-- proche (interpolées), et sensibilité à la perte réglée par la netteté
function Model.weightsFor(target)
    local w = weights()
    if not w then return nil end
    local elo = Model.modelElo(target)
    local c = w.centers
    local n = #c
    local i, j, t = n, n, 0
    if elo <= c[1] then i, j, t = 1, 1, 0
    elseif elo < c[n] then
        for k = 1, n - 1 do
            if elo <= c[k + 1] then
                i, j, t = k, k + 1, (elo - c[k]) / (c[k + 1] - c[k])
                break
            end
        end
    end
    local out = {}
    local a, b = w.bands[i], w.bands[j]
    for k = 1, Model.N do out[k] = a[k] + (b[k] - a[k]) * t end
    local scale = Model.sharpness(target)
    for _, k in ipairs({ 1, 2, 3, 4, 5, 6, 11, 30, 31 }) do out[k] = out[k] * scale end
    return out
end

--[[
  Probabilités de chaque coup candidat.
  lines : analyse MultiPV de Stockfish ; extra(pos, m) : bonus facultatif (style de jeu)
  Renvoie une liste { m, u, loss, p, visible } ou nil si le modèle est absent
]]
function Model.distribution(pos, lines, elo, ctx, extra)
    local w = Model.weightsFor(elo)
    if not w or not lines[1] then return nil end
    local bestWin = Model.winPercent(lines[1].cp)
    local cands = {}
    local maxs = -math.huge
    for rank, line in ipairs(lines) do
        local m = line.move and pos:findUci(line.move)
        if m then
            local after = pos:makeMove(m)
            local loss = math.max(0, bestWin - Model.winPercent(line.cp))
            local f = Model.features(pos, m, after, loss, rank, line.mate, ctx)
            local s = 0
            for k = 1, Model.N do s = s + w[k] * f[k] end
            if extra then s = s + extra(pos, m) end
            cands[#cands + 1] = { m = m, u = line.move, loss = loss, s = s, hang = f[11] }
            if s > maxs then maxs = s end
        end
    end
    if #cands == 0 then return nil end
    local total = 0
    for _, c in ipairs(cands) do
        c.p = math.exp(c.s - maxs)
        total = total + c.p
    end
    for _, c in ipairs(cands) do c.p = c.p / total end
    return cands
end

function Model.sample(cands, rnd)
    local r = (rnd or math.random)()
    for _, c in ipairs(cands) do
        r = r - c.p
        if r <= 0 then return c end
    end
    return cands[1]
end

return Model
