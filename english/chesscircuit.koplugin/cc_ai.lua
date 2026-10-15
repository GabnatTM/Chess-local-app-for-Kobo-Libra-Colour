--[[
  AI move choice: level (Elo 400 to 2500) and playing style.

  Stockfish always analyses at full strength and suggests several moves.
  We then pick among them like a player of the requested level would:
  the lower the level, the more imperfect moves are accepted, and
  sometimes a real blunder (like a beginner).
  The style adds a "taste": preferring checks, captures,
  development, king safety, traps…
]]

local Chess = require("cc_chess")

local AI = {}

AI.MIN_ELO = 400
AI.MAX_ELO = 2500

AI.STYLES = {
    { id = "equilibre", name = "Balanced",
      desc = "Plays naturally, with no particular preference." },
    { id = "attaquant", name = "Attacker",
      desc = "Looks for checks, captures and king attacks, even if it means taking risks." },
    { id = "stratege", name = "Strategist",
      desc = "Develops its pieces, controls the centre and plays quiet moves." },
    { id = "prudent", name = "Cautious",
      desc = "Keeps its king safe, trades when ahead and avoids complications." },
    { id = "piegeur", name = "Trickster",
      desc = "Sets traps: threats against big pieces and surprising moves." },
}

function AI.styleById(id)
    for _, s in ipairs(AI.STYLES) do
        if s.id == id then return s end
    end
    return AI.STYLES[1]
end

-- Winning chances (0..100) from an evaluation in centipawns
function AI.winPercent(cp)
    if cp > 9000 then return 100 end
    if cp < -9000 then return 0 end
    return 50 + 50 * (2 / (1 + math.exp(-0.00368208 * cp)) - 1)
end

-- "Temperature": tolerance for imperfect moves depending on the level
local function temperature(elo)
    local t = (elo - AI.MIN_ELO) / (AI.MAX_ELO - AI.MIN_ELO)
    if t < 0 then t = 0 elseif t > 1 then t = 1 end
    return 25 * (0.02 ^ t) -- 25 at 400 Elo, 0.5 at 2500 Elo
end

-- Probability of a real blunder (random move)
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

-- Suggested thinking time (ms) depending on the level
function AI.thinkTime(elo, base)
    base = base or 1000
    if elo >= 2200 then return base * 1.5 end
    if elo >= 1600 then return base end
    return math.max(500, base * 0.7)
end

-- Number of candidate moves to ask Stockfish for
function AI.multiPV(elo)
    if elo >= 2300 then return 3 end
    return 5
end

local function distance(a, b)
    return math.max(math.abs(Chess.fileOf(a) - Chess.fileOf(b)), math.abs(Chess.rankOf(a) - Chess.rankOf(b)))
end

local CENTER = { [27] = true, [28] = true, [35] = true, [36] = true } -- d4 e4 d5 e5

-- Style bonus (in "winning percentage points")
function AI.styleBonus(style, pos, m)
    if style == "equilibre" then return 0 end
    local us = pos.turn
    local them = Chess.other(us)
    local after = pos:makeMove(m)
    local gives_check = after:inCheck()
    local l = m.piece:lower()
    local opening = pos.fullmove <= 12
    local bonus = 0

    -- value of the enemy pieces attacked by the moved piece
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
            bonus = bonus + 0.8 -- pawn storm towards the enemy king
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
            -- rook on an open file
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
        if m.captured and diff >= 2 then bonus = bonus + 2 end -- simplify when ahead
        if gives_check then bonus = bonus - 0.5 end
        local mk = pos:kingSquare(us)
        if l == "p" and mk and math.abs(Chess.fileOf(m.from) - Chess.fileOf(mk)) <= 1
            and not opening then
            bonus = bonus - 1.5 -- don't weaken the king
        end
        if l == "k" and not m.castle and opening then bonus = bonus - 1 end
        -- moved piece still attacked? we don't like that
        if after:isAttacked(m.to, them) and not after:isAttacked(m.to, us) then bonus = bonus - 1.5 end
    elseif style == "piegeur" then
        if attacked_value >= 5 then bonus = bonus + 2.5 end
        if gives_check then bonus = bonus + 1.5 end
        -- a "non-obvious" move: neither a capture nor routine development
        if not m.captured and l ~= "p" and not m.castle then bonus = bonus + 0.5 end
        -- double attack
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
  Chooses a move.
  pos: position (the AI is to move)
  lines: Stockfish analysis (MultiPV) of this position
  rnd: random function (math.random by default)
  Returns: move (Chess table), uci
]]
function AI.chooseMove(pos, lines, elo, style, rnd)
    rnd = rnd or math.random
    local legal = pos:legalMoves()
    if #legal == 0 then return nil end
    if #legal == 1 then return legal[1], Chess.moveToUci(legal[1]) end

    -- Occasional blunder: a random move (but never when a mate is available)
    local best = lines[1]
    local hasMate = best and best.mate and best.mate > 0
    if not hasMate and rnd() < blunderChance(elo) then
        -- beginners often play "natural" moves: weight by style
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
            -- never miss a forced mate at high level
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

-- Player's new rating after a game (standard Elo formula)
function AI.updateRating(player, opponent, score, games_played)
    local k = (games_played or 0) < 10 and 40 or (player >= 2000 and 16 or 24)
    local expected = 1 / (1 + 10 ^ ((opponent - player) / 400))
    local new = player + k * (score - expected)
    return math.floor(new + 0.5)
end

---------------------------------------------------------------------------
-- Personalities of the simulated human players (tournaments, casual games)
---------------------------------------------------------------------------

--[[
  speed    : thinking time multiplier (small = plays fast)
  strength : real Elo bonus/penalty during games
  stress   : sensitivity to time pressure
  draw     : appetite for draws (0..1)
  resign   : resignation threshold (centipawns behind)
]]
AI.PERSONAS = {
    attaquant = { name = "Attacker", style = "attaquant", speed = 0.6, strength = -60, stress = 1.2,
        draw = 0.10, resign = 1200,
        desc = "Plays fast and attacks at all costs, even if it leaves weaknesses." },
    positionnel = { name = "Positional", style = "stratege", speed = 1.1, strength = 20, stress = 0.9,
        draw = 0.35, resign = 800,
        desc = "Calm and methodical: improves the pieces little by little." },
    solide = { name = "Solid", style = "prudent", speed = 1.2, strength = 30, stress = 0.8,
        draw = 0.55, resign = 900,
        desc = "Very hard to beat, likes safe positions and happily accepts draws." },
    tacticien = { name = "Tactician", style = "piegeur", speed = 0.9, strength = 0, stress = 1.0,
        draw = 0.20, resign = 1000,
        desc = "Spots combinations and loves setting traps." },
    zeitnot = { name = "Deep thinker", style = "equilibre", speed = 1.7, late_speed = 0.55,
        strength = 40, stress = 1.6, draw = 0.25, resign = 1000,
        desc = "Thinks for a very long time early on… and often ends up short of time." },
    blitzeur = { name = "Blitzer", style = "equilibre", speed = 0.35, strength = -40, stress = 0.6,
        draw = 0.20, resign = 1100,
        desc = "Plays almost instantly, on instinct. Dangerous when the clock is ticking." },
    equilibre = { name = "Balanced", style = "equilibre", speed = 1.0, strength = 0, stress = 1.0,
        draw = 0.30, resign = 900,
        desc = "A complete player with no obvious weakness." },
}
AI.PERSONA_IDS = { "attaquant", "positionnel", "solide", "tacticien", "zeitnot", "blitzeur", "equilibre" }

function AI.persona(id)
    return AI.PERSONAS[id] or AI.PERSONAS.equilibre
end

-- Time controls
AI.CADENCES = {
    blitz = { id = "blitz", name = "Blitz 3 + 5", base = 180, inc = 5, factor = 0.60 },
    rapide = { id = "rapide", name = "Rapid 10 + 5", base = 600, inc = 5, factor = 0.73 },
    long = { id = "long", name = "Rapid 15 + 10", base = 900, inc = 10, factor = 0.82 },
}

function AI.cadenceFactor(tc)
    if not tc then return 1 end
    for _, c in pairs(AI.CADENCES) do
        if c.base == tc.base and c.inc == tc.inc then return c.factor end
    end
    -- interpolate on the estimated total time (40 moves)
    local total = tc.base + 40 * (tc.inc or 0)
    if total >= 3600 then return 1 end
    return math.max(0.55, math.min(1, 0.55 + 0.45 * (total - 180) / 3400))
end

--[[
  Level actually played on this move.
  elo: displayed rating; tc: time control (nil = no clock)
  remaining: time left (s); persona: personality table
  rushed: time taken / "normal" time ratio (<1 = played fast)
]]
function AI.effectiveElo(elo, tc, persona, remaining, rushed)
    persona = persona or AI.PERSONAS.equilibre
    local e = elo + (persona.strength or 0)
    if tc then
        e = 400 + (e - 400) * AI.cadenceFactor(tc)
        -- clock stress
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
  "Human" thinking time (in seconds) for a move.
  ctx = { persona, remaining, opp_remaining, tc, fullmove, nlegal,
          lines (MultiPV analysis), recapture (bool), opp_last_think, rnd }
  Returns: seconds, and the "normal" reference time
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
            factor = factor * 0.45           -- obvious move
        else
            local close = 0
            for i = 2, #lines do
                if math.abs((lines[1].cp or 0) - (lines[i].cp or 0)) < 40 then close = close + 1 end
            end
            if close >= 2 and fm > 9 then factor = factor * 1.5 end -- complex position
        end
        if lines[1].mate then factor = factor * 0.6 end
    end
    if ctx.recapture then factor = factor * 0.4 end

    local speed = p.speed or 1
    if p.late_speed and fm > 24 then speed = p.late_speed end
    -- the opponent thought for a long time: we could think meanwhile
    if ctx.opp_last_think and ctx.opp_last_think > budget * 2 then factor = factor * 0.75 end
    -- ahead on the clock, allow a bit more time
    if ctx.opp_remaining and remaining > ctx.opp_remaining * 1.8 and remaining > 60 then
        factor = factor * 1.15
    end

    local t = budget * factor * speed * lognormal(rnd, 0.45)
    local reaction = 0.8 + rnd() * 0.9
    if ctx.recapture or ctx.nlegal == 1 then reaction = 0.5 + rnd() * 0.5 end
    t = math.max(t, reaction)
    -- never more than a quarter of the remaining time, and keep a margin
    t = math.min(t, remaining * 0.25 + inc * 0.5, math.max(0.4, remaining - 1.5))
    if remaining < 20 then t = math.min(t, 1.2 + rnd() * 1.5) end
    return t, budget
end

-- Does the engine accept a draw offer?
-- ai_cp: evaluation from the AI's point of view; ratio_time: AI time / player time
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
