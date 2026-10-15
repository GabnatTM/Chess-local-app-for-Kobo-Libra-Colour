--[[
  The coach: classifies moves (like chess.com) and explains
  in plain English what a move does on the board.
]]

local Chess = require("cc_chess")
local AI = require("cc_ai")

local Coach = {}

---------------------------------------------------------------------------
-- Move categories (pastel colours)
---------------------------------------------------------------------------

Coach.CATEGORIES = {
    brillant    = { label = "Brilliant",          symbol = "!!", color = {104, 205, 198}, gray = 0xB8, rank = 1 },
    super       = { label = "Great move",     symbol = "!",  color = {137, 176, 230}, gray = 0xC0, rank = 2 },
    meilleur    = { label = "Best move",     symbol = "★",  color = {150, 206, 138}, gray = 0xC8, rank = 3 },
    excellent   = { label = "Excellent",         symbol = "✓",  color = {178, 218, 150}, gray = 0xD0, rank = 4 },
    bon         = { label = "Good move",          symbol = "✓",  color = {205, 226, 180}, gray = 0xD8, rank = 5 },
    imprecision = { label = "Inaccuracy",       symbol = "?!", color = {244, 222, 128}, gray = 0xD0, rank = 6 },
    erreur      = { label = "Mistake",            symbol = "?",  color = {243, 182, 128}, gray = 0xB0, rank = 7 },
    manque      = { label = "Miss",       symbol = "✗",  color = {236, 160, 175}, gray = 0xA0, rank = 8 },
    gaffe       = { label = "Blunder",             symbol = "??", color = {228, 128, 128}, gray = 0x90, rank = 9 },
}
Coach.ORDER = { "brillant", "super", "meilleur", "excellent", "bon", "imprecision", "erreur", "manque", "gaffe" }

-- Arrow colour
Coach.BEST_ARROW = {120, 196, 120}

---------------------------------------------------------------------------
-- Piece names
---------------------------------------------------------------------------

local NAMES = {
    p = { "pawn", "m" }, n = { "knight", "m" }, b = { "bishop", "m" },
    r = { "rook", "f" }, q = { "queen", "f" }, k = { "king", "m" },
}

local sqName = Chess.sqName

-- persp = "joueur" (your move) or "adversaire" (the AI's move)
local function own(l, persp)
    local n = NAMES[l][1]
    if persp == "joueur" then return "your " .. n end
    return "their " .. n
end

local function enemy(l, persp)
    local n = NAMES[l][1]
    if persp == "joueur" then
        return "the opponent's " .. n
    end
    return "your " .. n
end

local function joinList(items)
    if #items == 0 then return "" end
    if #items == 1 then return items[1] end
    return table.concat(items, ", ", 1, #items - 1) .. " and " .. items[#items]
end
Coach.joinList = joinList

---------------------------------------------------------------------------
-- Tactical helpers
---------------------------------------------------------------------------

-- Winning chances (0..100) used to judge moves:
-- a slightly softer curve than the AI's, close to chess.com's judgements
function Coach.win(cp)
    if cp > 9000 then return 100 end
    if cp < -9000 then return 0 end
    return 50 + 50 * (2 / (1 + math.exp(-0.003 * cp)) - 1)
end

local function value(p)
    return Chess.VALUES[p:lower()]
end

local function lowestAttacker(pos, sq, by)
    local best
    for _, s in ipairs(pos:attackersOf(sq, by)) do
        local v = value(pos.board[s])
        if pos.board[s]:lower() == "k" then v = 100 end
        if not best or v < best then best = v end
    end
    return best
end

-- A piece is "hanging" if it can be taken profitably
local function isHanging(pos, sq)
    local p = pos.board[sq]
    if not p or p:lower() == "k" then return false end
    local c = Chess.colorOf(p)
    local them = Chess.other(c)
    local att = lowestAttacker(pos, sq, them)
    if not att then return false end
    local defended = #pos:attackersOf(sq, c) > 0
    if not defended then return true end
    return att < value(p)
end
Coach.isHanging = isHanging

local function hangingSet(pos, color)
    local set = {}
    for s = 0, 63 do
        local p = pos.board[s]
        if p and Chess.colorOf(p) == color and isHanging(pos, s) then set[s] = true end
    end
    return set
end

local function mobility(pos, sq)
    local n = 0
    local c = Chess.colorOf(pos.board[sq])
    for _, s in ipairs(pos:attacksFrom(sq)) do
        local p = pos.board[s]
        if not p or Chess.colorOf(p) ~= c then n = n + 1 end
    end
    return n
end

-- Is the move a sacrifice (offering material)?
function Coach.isSacrifice(pos, m)
    if m.promo then return false end
    local after = pos:makeMove(m)
    local mv = value(m.piece)
    if m.piece:lower() == "k" or mv < 3 then return false end
    local gained = m.captured and value(m.captured) or 0
    if mv - gained < 2 then return false end
    local them = Chess.other(pos.turn)
    local att = lowestAttacker(after, m.to, them)
    if not att then return false end
    local defended = #after:attackersOf(m.to, pos.turn) > 0
    return (not defended) or att < mv
end

local CENTER = { [27] = true, [28] = true, [35] = true, [36] = true }
local CENTER_PAWN = { [26] = true, [27] = true, [28] = true, [34] = true, [35] = true, [36] = true }

local function isPassed(pos, sq)
    local p = pos.board[sq]
    local c = Chess.colorOf(p)
    local enemyPawn = c == "w" and "p" or "P"
    local f, r = Chess.fileOf(sq), Chess.rankOf(sq)
    for df = -1, 1 do
        local ff = f + df
        if ff >= 0 and ff <= 7 then
            if c == "w" then
                for rr = r + 1, 7 do if pos.board[rr * 8 + ff] == enemyPawn then return false end end
            else
                for rr = r - 1, 0, -1 do if pos.board[rr * 8 + ff] == enemyPawn then return false end end
            end
        end
    end
    return true
end

local function fileStatus(pos, file, color)
    local ownPawn = color == "w" and "P" or "p"
    local enemyPawn = color == "w" and "p" or "P"
    local hasOwn, hasEnemy = false, false
    for r = 0, 7 do
        local p = pos.board[r * 8 + file]
        if p == ownPawn then hasOwn = true end
        if p == enemyPawn then hasEnemy = true end
    end
    if not hasOwn and not hasEnemy then return "open" end
    if not hasOwn then return "half-open" end
    return nil
end

---------------------------------------------------------------------------
-- What a move does
---------------------------------------------------------------------------

--[[
  Returns a list of phrases (third-person verbs) describing the move.
  warnings: flaws of the move (pieces left unprotected…)
]]
function Coach.describe(pos, m, persp)
    local phrases, warnings = {}, {}
    local us = pos.turn
    local them = Chess.other(us)
    local after = pos:makeMove(m)
    local l = m.piece:lower()
    local opening = pos.fullmove <= 12

    -- checkmate
    if after:inCheck() and #after:legalMoves() == 0 then
        return { "delivers checkmate" }, {}
    end

    if m.castle then
        phrases[#phrases + 1] = "castles, tucking the king away and bringing the rook into play"
    end

    -- capture
    if m.captured then
        local cl = m.captured:lower()
        local recapt = lowestAttacker(after, m.to, them)
        local gain = value(m.captured) - (recapt and value(m.piece) or 0)
        local target = enemy(cl, persp) .. " on " .. sqName(m.to)
        if m.enpassant then target = enemy("p", persp) .. " en passant" end
        if not recapt or gain > 0 then
            phrases[#phrases + 1] = "wins " .. target
        elseif gain == 0 then
            phrases[#phrases + 1] = "trades " .. own(l, persp) .. " for " .. target
        else
            phrases[#phrases + 1] = "takes " .. target
        end
    end

    if m.promo then
        phrases[#phrases + 1] = "promotes the pawn to a " .. NAMES[m.promo][1]
    end

    local gives_check = after:inCheck()
    if gives_check then
        phrases[#phrases + 1] = persp == "joueur" and "gives check to the opponent's king" or "puts your king in check"
    end

    -- development and centre
    if opening and (l == "n" or l == "b") and not m.captured then
        local back = us == "w" and 0 or 7
        if Chess.rankOf(m.from) == back then
            local f = Chess.fileOf(m.to)
            if l == "n" and (f == 0 or f == 7) then
                phrases[#phrases + 1] = "develops " .. own(l, persp)
                    .. " to the edge of the board, where it controls few squares"
            elseif f >= 2 and f <= 5 or l == "b" then
                phrases[#phrases + 1] = "develops " .. own(l, persp) .. " to an active square"
            else
                phrases[#phrases + 1] = "develops " .. own(l, persp)
            end
        end
    end
    if l == "p" and CENTER_PAWN[m.to] and pos.fullmove <= 15 and not m.captured then
        phrases[#phrases + 1] = "gains space in the centre"
    end

    -- opens lines for other pieces
    if not m.castle then
        local bestGain, bestSq = 0, nil
        for s = 0, 63 do
            local p = pos.board[s]
            if p and s ~= m.from and Chess.colorOf(p) == us then
                local pl = p:lower()
                if pl == "b" or pl == "r" or pl == "q" then
                    local g = mobility(after, s) - mobility(pos, s)
                    if g > bestGain then bestGain, bestSq = g, s end
                end
            end
        end
        if bestGain >= 3 then
            local pl = pos.board[bestSq]:lower()
            local kind = pl == "b" and "a diagonal" or (pl == "r" and "a line" or "lines")
            phrases[#phrases + 1] = "opens " .. kind .. " for " .. own(pl, persp) .. " on " .. sqName(bestSq)
        end
    end

    -- centre control by the moved piece
    if l ~= "p" and l ~= "k" then
        local before_c, after_c = 0, 0
        for _, s in ipairs(pos:attacksFrom(m.from)) do if CENTER[s] then before_c = before_c + 1 end end
        for _, s in ipairs(after:attacksFrom(m.to)) do if CENTER[s] then after_c = after_c + 1 end end
        if after_c - before_c >= 2 and pos.fullmove <= 25 then
            phrases[#phrases + 1] = "strengthens control of the central squares"
        end
    end

    -- rook on an open file
    if l == "r" and not m.castle then
        local st = fileStatus(after, Chess.fileOf(m.to), us)
        local st0 = fileStatus(pos, Chess.fileOf(m.from), us)
        if st and (Chess.fileOf(m.to) ~= Chess.fileOf(m.from) or not st0) then
            phrases[#phrases + 1] = "puts " .. own("r", persp) .. " on a" .. (st == "open" and "n open" or " half-open") .. " file, where it becomes active"
        end
    end

    -- passed pawn
    if l == "p" and not m.promo and isPassed(after, m.to) then
        local r = Chess.rankOf(m.to)
        local adv = us == "w" and r or (7 - r)
        if adv >= 4 then
            phrases[#phrases + 1] = "pushes a passed pawn towards promotion"
        end
    end

    -- moving to safety / protection
    local hangBefore = hangingSet(pos, us)
    local hangAfter = hangingSet(after, us)
    if hangBefore[m.from] and not hangAfter[m.to] and not m.captured then
        phrases[#phrases + 1] = "moves " .. own(l, persp) .. " to safety"
    end
    for s in pairs(hangBefore) do
        if s ~= m.from and not hangAfter[s] and after.board[s] then
            phrases[#phrases + 1] = "protects " .. own(after.board[s]:lower(), persp) .. " on " .. sqName(s)
            break
        end
    end

    -- threats created by the moved piece
    local targets = {}
    local hangThemBefore = hangingSet(pos, them)
    for _, s in ipairs(after:attacksFrom(m.to)) do
        local p = after.board[s]
        if p and Chess.colorOf(p) == them then
            local pl = p:lower()
            if pl == "k" then
                -- already mentioned through the check
            elseif (isHanging(after, s) and not hangThemBefore[s]) or (pl == "q" and l ~= "q") then
                targets[#targets + 1] = { sq = s, l = pl, v = value(p) }
            end
        end
    end
    table.sort(targets, function(a, b) return a.v > b.v end)
    local bigTargets = 0
    for _, t in ipairs(targets) do if t.v >= 3 then bigTargets = bigTargets + 1 end end
    if (bigTargets >= 2) or (gives_check and bigTargets >= 1) then
        local names = {}
        if gives_check then names[#names + 1] = persp == "joueur" and "the opponent's king" or "your king" end
        for _, t in ipairs(targets) do
            if t.v >= 3 and #names < 3 then names[#names + 1] = enemy(t.l, persp) .. " on " .. sqName(t.sq) end
        end
        phrases[#phrases + 1] = "makes a fork, attacking " .. joinList(names)
    elseif #targets >= 1 then
        local t = targets[1]
        phrases[#phrases + 1] = "threatens " .. enemy(t.l, persp) .. " on " .. sqName(t.sq)
    end

    -- pin
    if l == "b" or l == "r" or l == "q" then
        local dirs = {}
        if l ~= "r" then for _, d in ipairs({{1,1},{1,-1},{-1,1},{-1,-1}}) do dirs[#dirs + 1] = d end end
        if l ~= "b" then for _, d in ipairs({{1,0},{-1,0},{0,1},{0,-1}}) do dirs[#dirs + 1] = d end end
        for _, d in ipairs(dirs) do
            local s = Chess.offset(m.to, d[1], d[2])
            local first
            while s do
                local p = after.board[s]
                if p then
                    if not first then
                        if Chess.colorOf(p) ~= them or p:lower() == "k" then break end
                        first = { sq = s, l = p:lower() }
                    else
                        if Chess.colorOf(p) == them and (p:lower() == "k" or (p:lower() == "q" and first.l ~= "q"))
                            and value(m.piece) <= 9 then
                            local behind = p:lower() == "k" and (persp == "joueur" and "their king" or "your king")
                                or (persp == "joueur" and "their queen" or "your queen")
                            phrases[#phrases + 1] = "pins " .. enemy(first.l, persp) .. " on " .. sqName(first.sq)
                                .. " to " .. behind
                        end
                        break
                    end
                end
                s = Chess.offset(s, d[1], d[2])
            end
        end
    end

    -- flaws: pieces left hanging
    if hangAfter[m.to] and not (m.captured and value(m.captured) >= value(m.piece)) then
        warnings[#warnings + 1] = "leaves " .. own(after.board[m.to]:lower(), persp) .. " on " .. sqName(m.to)
            .. " without enough protection"
    end
    for s in pairs(hangAfter) do
        if s ~= m.to and hangBefore[s] and s ~= m.from then
            local pl = after.board[s]:lower()
            warnings[#warnings + 1] = "does not deal with the threat to " .. own(pl, persp) .. " on " .. sqName(s)
            break
        end
    end
    for s in pairs(hangAfter) do
        if s ~= m.to and not hangBefore[s] then
            warnings[#warnings + 1] = "exposes " .. own(after.board[s]:lower(), persp) .. " on " .. sqName(s)
                .. ", which is no longer protected"
            break
        end
    end

    local trivial = false
    if #phrases == 0 then
        trivial = true
        if l == "k" then
            phrases[#phrases + 1] = "moves the king"
        elseif l == "p" then
            phrases[#phrases + 1] = "advances a pawn to gain space"
        else
            phrases[#phrases + 1] = "moves " .. own(l, persp) .. " to " .. sqName(m.to)
        end
    end
    return phrases, warnings, trivial
end

---------------------------------------------------------------------------
-- Classifying a move
---------------------------------------------------------------------------

--[[
  before: analysis of the position BEFORE the move (player to move), MultiPV >= 2
  after_cp: evaluation after the move, from the player's point of view
  Returns the category id and the winning chances before/after.
]]
function Coach.classify(pos, m, before, after_cp)
    local uci = Chess.moveToUci(m)
    local best = before[1]
    if not best then return "bon", 50, 50 end
    local winB = Coach.win(best.cp)
    local winA = Coach.win(after_cp)
    local loss = math.max(0, winB - winA)
    local nlegal = #pos:legalMoves()

    if uci == best.move or loss < 0.3 then
        if Coach.isSacrifice(pos, m) and winA >= 50 and winB < 97 then
            return "brillant", winB, winA
        end
        -- "Great move": the only good move, and not just an obvious recapture
        local obvious = m.captured and isHanging(pos, m.to)
        if nlegal > 1 and before[2] and uci == best.move and not obvious then
            local w2 = Coach.win(before[2].cp)
            if winB - w2 >= 15 and winB >= 40 then return "super", winB, winA end
        end
        return "meilleur", winB, winA
    end
    if loss <= 2 then
        if Coach.isSacrifice(pos, m) and winA >= 55 and winB < 97 then return "brillant", winB, winA end
        return "excellent", winB, winA
    end
    if loss <= 5 then return "bon", winB, winA end
    if loss > 10 and winB >= 70 and winA >= 35 then return "manque", winB, winA end
    if loss <= 10 then return "imprecision", winB, winA end
    if loss <= 20 then return "erreur", winB, winA end
    return "gaffe", winB, winA
end

-- Move accuracy (0..100), formula inspired by Lichess
function Coach.accuracy(winB, winA)
    local d = math.max(0, winB - winA)
    local a = 103.1668 * math.exp(-0.04354 * d) - 3.1669
    if a > 100 then a = 100 elseif a < 0 then a = 0 end
    return a
end

---------------------------------------------------------------------------
-- Coach text
---------------------------------------------------------------------------

local function fmtEval(cp)
    if cp >= 9000 then
        return "mate in " .. math.floor((10000 - cp) / 10 + 0.5) .. " for you"
    elseif cp <= -9000 then
        return "mate in " .. math.floor((cp + 10000) / 10 + 0.5) .. " for the opponent"
    end
    local v = cp / 100
    local s = string.format("%+.1f", v)
    return s
end
Coach.fmtEval = fmtEval

function Coach.evalSentence(cp)
    if cp >= 9000 then return "You have a forced mate." end
    if cp <= -9000 then return "The opponent has a forced mate." end
    local a = math.abs(cp)
    local who = cp > 0 and "you" or "the opponent"
    if a < 40 then return "The position is balanced." end
    if a < 120 then return "Slight advantage for " .. who .. "." end
    if a < 300 then return "Clear advantage for " .. who .. "." end
    return "Decisive advantage for " .. who .. "."
end

local VERDICT = {
    brillant = "A brilliant sacrifice: you give up material for something bigger!",
    super = "The only good move in the position. Well found!",
    meilleur = "That's exactly the move I'd recommend.",
    excellent = "Excellent, almost as strong as the best move.",
    bon = "A decent move, but there was something more precise.",
    imprecision = "An inaccuracy: you lose a little ground.",
    erreur = "A mistake: the balance of the game tips over.",
    manque = "A missed chance: you could have taken a big advantage.",
    gaffe = "A blunder: this move spoils the position.",
}

-- Plays a sequence of uci moves and returns their notation (for the "idea" of the move)
local function pvSan(pos, pv, n)
    local res = {}
    local p = pos
    for i = 1, math.min(n, #pv) do
        local m = p:findUci(pv[i])
        if not m then break end
        res[#res + 1] = { san = p:san(m), m = m, pos = p }
        p = p:makeMove(m)
    end
    return res
end

local function capitalize(s)
    return s:sub(1, 1):upper() .. s:sub(2)
end

--[[
  Builds the full explanation.
  info = {
    pos = position before the move, move = move played, cls = category,
    before = analysis lines before, after_lines = analysis after (opponent to move),
    after_cp = eval after (player's point of view)
  }
  Returns { title, paragraphs = {...} }
]]
function Coach.explain(info)
    local pos, m, cls = info.pos, info.move, info.cls
    local cat = Coach.CATEGORIES[cls]
    local san = pos:san(m)
    local paras = {}

    paras[#paras + 1] = VERDICT[cls]

    -- what your move does
    local ph, warn = Coach.describe(pos, m, "joueur")
    local s = "Your move " .. san .. " " .. joinList(ph)
    if #warn > 0 and Coach.CATEGORIES[cls].rank >= 5 then
        s = s .. ", but it " .. joinList(warn)
    end
    paras[#paras + 1] = s .. "."

    -- the opponent's reply (if the move is bad)
    local after = pos:makeMove(m)
    local reply = info.after_lines and info.after_lines[1]
    if reply and Coach.CATEGORIES[cls].rank >= 6 then
        local rm = after:findUci(reply.move)
        if rm then
            local rph, _, trivial = Coach.describe(after, rm, "adversaire")
            local t
            if not trivial then
                t = "The problem: the opponent can reply " .. after:san(rm) .. ", which " .. joinList(rph) .. "."
            end
            if reply.mate and reply.mate > 0 then
                t = (t and (t .. " ") or "") .. "The opponent now has mate in " .. reply.mate .. "!"
            end
            if t then paras[#paras + 1] = t end
        end
    end

    -- the best move
    local best = info.before and info.before[1]
    if best and best.move ~= Chess.moveToUci(m) then
        local bm = pos:findUci(best.move)
        if bm then
            local bph = Coach.describe(pos, bm, "joueur")
            local t = "The best move was " .. pos:san(bm) .. " (green arrow): it " .. joinList(bph) .. "."
            local line = pvSan(pos, best.pv or {}, 3)
            if #line >= 3 then
                local ideaPh = Coach.describe(line[3].pos, line[3].m, "joueur")
                t = t .. " The idea: if the opponent replies " .. line[2].san .. ", you continue with "
                    .. line[3].san .. ", which " .. joinList(ideaPh) .. "."
            end
            paras[#paras + 1] = t
        end
    elseif best then
        local line = pvSan(pos, best.pv or {}, 3)
        if #line >= 3 then
            local ideaPh = Coach.describe(line[3].pos, line[3].m, "joueur")
            paras[#paras + 1] = "The natural follow-up: after " .. line[2].san .. ", you can play "
                .. line[3].san .. ", which " .. joinList(ideaPh) .. "."
        end
    end

    if info.after_cp then
        paras[#paras + 1] = "Evaluation: " .. fmtEval(info.after_cp) .. ". " .. Coach.evalSentence(info.after_cp)
    end

    return { title = cat.label, symbol = cat.symbol, paragraphs = paras, capitalize = capitalize }
end

-- Hint for the current position (without playing).
-- Returns a discreet hint (step 1) and the full explanation (step 2).
function Coach.hint(pos, lines)
    local best = lines and lines[1]
    if not best then return nil end
    local bm = pos:findUci(best.move)
    if not bm then return nil end
    local ph = Coach.describe(pos, bm, "joueur")
    local first = ph[1] or ""
    local theme
    if first:find("checkmate", 1, true) then theme = "There is mate in one!"
    elseif first:find("^wins") then theme = "There is material to win."
    elseif first:find("fork", 1, true) then theme = "Look for a double attack."
    elseif first:find("check", 1, true) then theme = "Think about attacking the enemy king."
    elseif first:find("to safety", 1, true) and not bm.castle then theme = "One of your pieces is under attack."
    elseif bm.castle then theme = "Think about your king's safety."
    elseif first:find("develops", 1, true) then theme = "Think about developing your pieces."
    elseif first:find("centre", 1, true) then theme = "Think about the centre."
    elseif first:find("threatens", 1, true) or first:find("pins", 1, true) then theme = "You can create a threat."
    end
    local l = bm.piece:lower()
    local vague = "Look at your " .. NAMES[l][1] .. " on " .. sqName(bm.from) .. "."
    if theme then vague = vague .. " " .. theme end
    local full = "The suggested move is " .. pos:san(bm) .. ": it " .. joinList(ph) .. "."
    return vague, full
end

-- Simple sentence describing a move (for reviewing moves without annotation)
-- persp = "joueur" (your move) or "adversaire" (opponent)
function Coach.moveSentence(pos, m, persp)
    local san = pos:san(m)
    local ph = Coach.describe(pos, m, persp)
    if persp == "joueur" then
        return "Your move " .. san .. " " .. joinList(ph) .. "."
    end
    return "The opponent played " .. san .. ": this move " .. joinList(ph) .. "."
end

return Coach
