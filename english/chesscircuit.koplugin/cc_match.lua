--[[
  A game against the AI, whatever the mode:
   - "coach"      : no clock, coach, hints, eval, free takebacks
   - "libre"      : casual training game (with or without a clock)
   - "tournoi", "candidats", "monde" : competitive games with a clock

  This file draws nothing: the screen listens through onUpdate(event).
]]

local Chess = require("cc_chess")
local AI = require("cc_ai")
local Coach = require("cc_coach")

local Match = {}
Match.__index = Match

local MATE = 10000

---------------------------------------------------------------------------
-- Creating a new game (saveable data)
---------------------------------------------------------------------------

--[[
  params = {
    mode = "coach" | "libre" | "tournoi" | "candidats" | "monde",
    player_color = "w" | "b",
    opp = { id, name, elo, persona, style, title },
    tc = { base = seconds, inc = seconds } or nil (no clock),
    label = displayed text (e.g. "Paris Open — round 3")
  }
]]
function Match.newGame(params)
    local g = {
        version = 2,
        mode = params.mode or "coach",
        start_fen = params.start_fen or Chess.START_FEN,
        moves = {},
        cursor = 0,
        player_color = params.player_color or "w",
        opp = params.opp or { name = "AI", elo = 1200, persona = "equilibre" },
        tc = params.tc,
        label = params.label,
        annotations = {},
        lines = {},
        evals = {},
        ai_cache = {},
        think = {},
        turn_spent = 0,
        resign_count = 0,
        created = os.time(),
    }
    if params.tc then
        g.clock = { w = params.tc.base, b = params.tc.base }
    end
    return g
end

local function trimLines(lines, n)
    local res = {}
    for i = 1, math.min(n or 2, #lines) do
        local l = lines[i]
        local pv = {}
        for j = 1, math.min(4, #(l.pv or {})) do pv[j] = l.pv[j] end
        res[i] = { cp = l.cp, mate = l.mate, move = l.move, pv = pv }
    end
    return res
end

---------------------------------------------------------------------------
-- Construction
---------------------------------------------------------------------------

--[[
  opts = {
    game, engine, settings (table with think_ms),
    rnd, now (function -> seconds), schedule(seconds, fn),
    onUpdate(ev), onFinish(match), save()
  }
]]
function Match.new(opts)
    local self = setmetatable({}, Match)
    self.g = opts.game
    self.engine = opts.engine
    self.settings = opts.settings or { think_ms = 1000 }
    self.rnd = opts.rnd or math.random
    self.now = opts.now or os.time
    self.schedule = opts.schedule
    self.onUpdate = opts.onUpdate or function() end
    self.onFinish = opts.onFinish or function() end
    self._save = opts.save or function() end
    self.gen = 0
    self.paused = true
    self.thinking = false
    self.pending = {}
    local g = self.g
    g.annotations = g.annotations or {}
    g.lines = g.lines or {}
    g.evals = g.evals or {}
    g.ai_cache = g.ai_cache or {}
    g.think = g.think or {}
    -- saved numeric keys may come back as strings
    local ann = {}
    for k, v in pairs(g.annotations) do ann[tonumber(k)] = v end
    g.annotations = ann
    local th = {}
    for k, v in pairs(g.think) do th[tonumber(k)] = v end
    g.think = th
    self:_rebuild()
    if g.cursor == nil or g.cursor > #g.moves then g.cursor = #g.moves end
    return self
end

function Match:save() self._save() end

function Match:_rebuild()
    local g = self.g
    self.positions = { Chess.new(g.start_fen) }
    self.sans = {}
    self.keycount = {}
    self.keycount[self.positions[1]:key()] = 1
    for i, uci in ipairs(g.moves) do
        local p = self.positions[i]
        local m = p:findUci(uci)
        if not m then
            for j = #g.moves, i, -1 do g.moves[j] = nil end
            break
        end
        self.sans[i] = p:san(m)
        local n = p:makeMove(m)
        self.positions[i + 1] = n
        local k = n:key()
        self.keycount[k] = (self.keycount[k] or 0) + 1
    end
end

---------------------------------------------------------------------------
-- Information
---------------------------------------------------------------------------

function Match:isCoach() return self.g.mode == "coach" end
function Match:isTimed() return self.g.tc ~= nil end
function Match:isCompetition()
    local m = self.g.mode
    return m == "tournoi" or m == "candidats" or m == "monde"
end
function Match:ended() return self.g.result ~= nil end
function Match:atEnd() return self.g.cursor == #self.g.moves end
function Match:livePos() return self.positions[#self.g.moves + 1] end
function Match:viewPos() return self.positions[self.g.cursor + 1] end
function Match:aiColor() return Chess.other(self.g.player_color) end
function Match:plyCount() return #self.g.moves end
function Match:isThinking() return self.thinking end
function Match:persona() return AI.persona(self.g.opp.persona) end

function Match:playerToMove()
    return not self:ended() and self:livePos().turn == self.g.player_color
end

-- Can the player move on the displayed position?
function Match:canPlayHere()
    if self.thinking then return false end
    local g = self.g
    if self:isCoach() then
        local pos = self:viewPos()
        if pos.turn ~= g.player_color then return false end
        if self:atEnd() and self:ended() then return false end
        return true
    end
    return self:atEnd() and self:playerToMove() and not self.paused
end

function Match:canNavigate()
    return self:isCoach() or self:ended()
end

function Match:canUseEval()
    return self:isCoach() or self:ended()
end

---------------------------------------------------------------------------
-- Start / pause (clock)
---------------------------------------------------------------------------

function Match:resume()
    if not self.paused then return end
    self.paused = false
    self.gen = self.gen + 1
    self.last_stamp = self.now()
    if self:ended() then return end
    if self:isTimed() then self:_startTicks() end
    if self:atEnd() and not self:playerToMove() then
        self:_aiTurn()
    elseif self:isCoach() then
        self:_preAnalyseView()
    end
end

function Match:pause()
    self.premove = nil
    if self.paused then return end
    self:_accrue()
    self.paused = true
    self.gen = self.gen + 1
    self.thinking = false
    if self.engine then self.engine:cancelAll() end
    self.pending = {}
    self:save()
end

function Match:_accrue()
    local g = self.g
    if not self:isTimed() or self.paused or self:ended() then return end
    local now = self.now()
    local d = now - (self.last_stamp or now)
    self.last_stamp = now
    if d < 0 then d = 0 end
    if d > 3 then d = 3 end -- sleep or big slowdown: don't count it
    local side = self:livePos().turn
    g.clock[side] = g.clock[side] - d
    g.turn_spent = (g.turn_spent or 0) + d
end

function Match:clock(color)
    if not self:isTimed() then return nil end
    return math.max(0, self.g.clock[color])
end

function Match:_startTicks()
    local gen = self.gen
    local function tick()
        if gen ~= self.gen or self.paused or self:ended() then return end
        self:_accrue()
        if self:_checkFlag() then return end
        self.onUpdate("clock")
        self.schedule(1, tick)
    end
    self.schedule(1, tick)
end

local function canMate(pos, color)
    local minors, others = 0, 0
    for s = 0, 63 do
        local p = pos.board[s]
        if p and Chess.colorOf(p) == color then
            local l = p:lower()
            if l == "n" or l == "b" then minors = minors + 1
            elseif l ~= "k" then others = others + 1 end
        end
    end
    return others > 0 or minors >= 2
end

function Match:_checkFlag()
    local g = self.g
    local side = self:livePos().turn
    if g.clock[side] > 0 then return false end
    g.clock[side] = 0
    local other = Chess.other(side)
    if not canMate(self:livePos(), other) then
        self:_finish("1/2-1/2", "time out, insufficient material")
    else
        self:_finish(other == "w" and "1-0" or "0-1",
            side == g.player_color and "lost on time" or "opponent ran out of time")
    end
    return true
end

---------------------------------------------------------------------------
-- Moves
---------------------------------------------------------------------------

function Match:_push(m, byAI)
    local g = self.g
    local wasEnd = self:atEnd()
    local p = self:livePos()
    local mover = p.turn
    if self:isTimed() then
        self:_accrue()
        g.clock[mover] = g.clock[mover] + (g.tc.inc or 0)
    end
    g.think[#g.moves + 1] = g.turn_spent or 0
    g.turn_spent = 0
    self.sans[#g.moves + 1] = p:san(m)
    g.moves[#g.moves + 1] = Chess.moveToUci(m)
    local n = p:makeMove(m)
    self.positions[#self.positions + 1] = n
    local k = n:key()
    self.keycount[k] = (self.keycount[k] or 0) + 1
    if wasEnd or not byAI then g.cursor = #g.moves end
    local st = n:status(self.keycount[k])
    if st then
        self:_finish(st.result, st.reason)
    end
end

function Match:_truncate(n)
    local g = self.g
    for i = #g.moves, n + 1, -1 do
        local k = self.positions[i + 1]:key()
        self.keycount[k] = (self.keycount[k] or 1) - 1
        g.moves[i] = nil
        g.annotations[i] = nil
        g.think[i] = nil
        self.positions[i + 1] = nil
        self.sans[i] = nil
    end
    g.cursor = n
    if g.result then
        g.result, g.reason, g.score = nil, nil, nil
    end
end

function Match:playerMove(m)
    if not self:canPlayHere() then return false end
    local g = self.g
    local uci = Chess.moveToUci(m)
    if g.cursor < #g.moves then
        if g.moves[g.cursor + 1] == uci then
            -- same move as in the game: just step forward
            g.cursor = g.cursor + 1
            self:save()
            self.onUpdate("nav")
            self:_autoAdvance()
            return true
        end
        -- new move: the rest of the game is replaced
        self.gen = self.gen + 1
        if self.engine then self.engine:cancelAll() end
        self.pending = {}
        self:_truncate(g.cursor)
        g.takeback = true
    end
    local posBefore = self:livePos()
    if self:isCoach() then self:_requestLines(posBefore, 2) end
    self:_push(m, false)
    self:save()
    self.onUpdate("move")
    if self:ended() then
        if self:isCoach() then self:_annotate(#g.moves) end
        return true
    end
    self:_aiTurn()
    return true
end

-- After going back to a move already played: replay the AI's known reply
function Match:_autoAdvance()
    local g = self.g
    if g.cursor < #g.moves then
        if self:viewPos().turn ~= g.player_color then
            local gen = self.gen
            self.schedule(0.7, function()
                if gen ~= self.gen then return end
                if g.cursor < #g.moves and self:viewPos().turn ~= g.player_color then
                    g.cursor = g.cursor + 1
                    self:save()
                    self.onUpdate("nav")
                    self:_preAnalyseView()
                end
            end)
        else
            self:_preAnalyseView()
        end
    elseif not self:ended() and not self:playerToMove() and not self.thinking then
        self:_aiTurn()
    else
        self:_preAnalyseView()
    end
end

---------------------------------------------------------------------------
-- AI turn
---------------------------------------------------------------------------

function Match:_storeLines(pos, lines, keep)
    local g = self.g
    local key = pos:key()
    if lines[1] then
        g.evals[key] = pos.turn == "w" and lines[1].cp or -lines[1].cp
        if keep then
            local old = g.lines[key]
            if not old or #old <= #lines then g.lines[key] = trimLines(lines, keep) end
        end
    end
end

local function engineTime(eff)
    if eff < 1200 then return 350 end
    if eff < 1800 then return 600 end
    if eff < 2200 then return 900 end
    return 1300
end

function Match:_aiTurn()
    local g = self.g
    if self:ended() or not self:atEnd() or self.paused then return end
    local pos = self:livePos()
    if pos.turn == g.player_color then return end
    self.thinking = true
    self.onUpdate("thinking")
    local gen = self.gen
    local key = pos:key()
    local opp = g.opp
    local persona = self:persona()
    local style = opp.style or persona.style

    if self:isCoach() then
        local function decide(lines)
            if gen ~= self.gen then return end
            self:_annotate(#g.moves)
            local m
            local uci = g.ai_cache[key]
            if uci then m = pos:findUci(uci) end
            if not m then
                m = AI.chooseMove(pos, lines, opp.elo, style, self.rnd)
                if m then g.ai_cache[key] = Chess.moveToUci(m) end
            end
            self:_aiPlay(m)
        end
        local cached = g.lines[key]
        if g.ai_cache[key] and cached then
            self.schedule(0.5, function() decide(cached) end)
        else
            local think = math.max(AI.thinkTime(opp.elo, self.settings.think_ms or 1000), 600)
            self.engine:analyse(pos:fen(), AI.multiPV(opp.elo), think, function(lines)
                if gen ~= self.gen then return end
                self:_storeLines(pos, lines, 2)
                decide(lines)
            end)
        end
        return
    end

    -- "Human" opponent (casual, tournament…)
    local timed = self:isTimed()
    local aiColor = pos.turn
    local remaining = timed and g.clock[aiColor] or nil
    local eff0 = AI.effectiveElo(opp.elo, g.tc, persona, remaining)
    local started = self.now()
    self.engine:analyse(pos:fen(), AI.multiPV(eff0), engineTime(eff0), function(lines)
        if gen ~= self.gen then return end
        self:_storeLines(pos, lines, nil)
        -- resign?
        local cp = lines[1] and lines[1].cp
        if cp and cp <= -(persona.resign or 900) and pos.fullmove >= 12 then
            g.resign_count = (g.resign_count or 0) + 1
        else
            g.resign_count = 0
        end
        if g.resign_count >= 2 then
            self.thinking = false
            self:_finish(g.player_color == "w" and "1-0" or "0-1", "opponent resigned")
            return
        end
        local m = AI.chooseMove(pos, lines, eff0, style, self.rnd)
        if not m then return end
        if not timed then
            local delay = 0.6 + self.rnd() * 1.4 - (self.now() - started)
            if delay < 0.05 then
                self:_aiPlay(m)
            else
                self.schedule(delay, function() if gen == self.gen then self:_aiPlay(m) end end)
            end
            return
        end
        self:_accrue()
        local lastUci = g.moves[#g.moves]
        local prev = lastUci and self.positions[#g.moves]:findUci(lastUci)
        local recapture = prev and prev.captured and m.captured and m.to == prev.to
        local think, budget = AI.humanThinkTime{
            persona = persona, remaining = g.clock[aiColor], opp_remaining = g.clock[g.player_color],
            tc = g.tc, fullmove = pos.fullmove, nlegal = #pos:legalMoves(), lines = lines,
            recapture = recapture, opp_last_think = g.think[#g.moves], rnd = self.rnd,
        }
        local rushed = think / math.max(0.5, budget)
        if rushed < 0.7 then
            local eff1 = AI.effectiveElo(opp.elo, g.tc, persona, g.clock[aiColor], rushed)
            if eff1 < eff0 - 30 then
                m = AI.chooseMove(pos, lines, eff1, style, self.rnd) or m
            end
        end
        local wait = think - (g.turn_spent or 0)
        if wait <= 0.05 then
            self:_aiPlay(m)
        else
            self.schedule(wait, function() if gen == self.gen then self:_aiPlay(m) end end)
        end
    end)
end

function Match:_aiPlay(m)
    if self:ended() or not m then
        self.thinking = false
        return
    end
    self:_push(m, true)
    self.thinking = false
    self:save()
    self.onUpdate("move")
    if self:ended() then
        self.premove = nil
        return
    end
    if self:isCoach() then self:_preAnalyseView() end
    -- premove prepared while the opponent was thinking
    local pm = self.premove
    self.premove = nil
    if pm then
        local pos = self:livePos()
        local found
        for _, mv in ipairs(pos:legalMovesFrom(pm.from)) do
            if mv.to == pm.to and (not mv.promo or mv.promo == (pm.promo or "q")) then found = mv break end
        end
        if found then
            local gen = self.gen
            self.schedule(0.05, function()
                if gen == self.gen and self:canPlayHere() then self:playerMove(found) end
            end)
        else
            self.onUpdate("premove_cancelled")
        end
    end
end

-- Premoves (games without coach)
function Match:premoveAllowed()
    return not self:isCoach() and not self:ended() and self:atEnd() and not self:playerToMove() and not self.paused
end

function Match:setPremove(from, to)
    self.premove = { from = from, to = to, promo = "q" }
end

function Match:clearPremove()
    self.premove = nil
end

---------------------------------------------------------------------------
-- Analyses (coach, eval)
---------------------------------------------------------------------------

function Match:_requestLines(pos, multipv, cb)
    local g = self.g
    local key = pos:key()
    if g.lines[key] and #g.lines[key] >= multipv then
        if cb then cb() end
        return
    end
    if pos:status() then return end
    if self.pending[key] then return end
    self.pending[key] = true
    local gen = self.gen
    self.engine:analyse(pos:fen(), multipv, self.settings.think_ms or 1000, function(lines)
        if gen ~= self.gen then return end
        self.pending[key] = nil
        self:_storeLines(pos, lines, multipv)
        -- annotate the moves waiting for this analysis
        for ply = 1, #g.moves do
            if not g.annotations[ply] and (self.positions[ply]:key() == key or self.positions[ply + 1]:key() == key) then
                self:_annotate(ply)
            end
        end
        self:save()
        if cb then cb() end
        self.onUpdate("analysis")
    end)
end

function Match:_preAnalyseView()
    if not self:isCoach() or self.paused then return end
    local pos = self:viewPos()
    if pos.turn == self.g.player_color and not self:ended() then
        self:_requestLines(pos, 2)
    end
end

-- Evaluation (White's point of view) of the position after `idx` moves
function Match:evalAt(idx)
    local pos = self.positions[idx + 1]
    if not pos then return nil end
    local st = pos:status(self.keycount[pos:key()])
    if st then
        if st.result == "1-0" then return MATE end
        if st.result == "0-1" then return -MATE end
        return 0
    end
    return self.g.evals[pos:key()]
end

function Match:requestEval(idx)
    if not self:canUseEval() then return end
    local pos = self.positions[idx + 1]
    if not pos or self:evalAt(idx) then return end
    self:_requestLines(pos, self:isCoach() and 2 or 1)
end

-- Coach analysis of a finished game (all your moves)
function Match:analyseForCoach()
    local g = self.g
    for i = 1, #g.moves do
        local pos = self.positions[i]
        if pos.turn == g.player_color then
            self:_requestLines(pos, 2)
            self:_requestLines(self.positions[i + 1], 1)
        end
    end
end

function Match:analysisProgress()
    local g = self.g
    local done, total = 0, 0
    for i = 1, #g.moves do
        if self.positions[i].turn == g.player_color then
            total = total + 1
            if self:annotation(i) then done = done + 1 end
        end
    end
    return done, total
end

-- Full game analysis (for the end-of-game graph)
function Match:analyseAll(cb)
    local g = self.g
    local missing = {}
    for i = 0, #g.moves do
        if self:evalAt(i) == nil then missing[#missing + 1] = i end
    end
    if #missing == 0 then if cb then cb() end return end
    local saved = self.settings.think_ms
    for n, i in ipairs(missing) do
        local pos = self.positions[i + 1]
        local key = pos:key()
        if not self.pending[key] then
            self.pending[key] = true
            local gen = self.gen
            self.engine:analyse(pos:fen(), 1, math.min(400, saved or 400), function(lines)
                if gen ~= self.gen then return end
                self.pending[key] = nil
                self:_storeLines(pos, lines, nil)
                if n == #missing then
                    self:save()
                    if cb then cb() end
                    self.onUpdate("analysis")
                end
            end)
        end
    end
end

---------------------------------------------------------------------------
-- Coach: annotations and explanations
---------------------------------------------------------------------------

function Match:_afterCp(ply)
    local g = self.g
    local posAfter = self.positions[ply + 1]
    local st = posAfter:status(self.keycount[posAfter:key()])
    if st then
        if st.result == "1/2-1/2" then return 0 end
        return MATE -- the player just delivered mate
    end
    local after = g.lines[posAfter:key()]
    if after and after[1] then return -after[1].cp end
    local ev = g.evals[posAfter:key()]
    if ev then return g.player_color == "w" and ev or -ev end
    return nil
end

function Match:_annotate(ply)
    local g = self.g
    if g.annotations[ply] or not self:isCoach() then return end
    local posBefore = self.positions[ply]
    if not posBefore or posBefore.turn ~= g.player_color then return end
    local before = g.lines[posBefore:key()]
    local after_cp = self:_afterCp(ply)
    if not before or not before[1] or after_cp == nil then return end
    local m = posBefore:findUci(g.moves[ply])
    if not m then return end
    local cls, winB, winA = Coach.classify(posBefore, m, before, after_cp)
    g.annotations[ply] = { cls = cls, after_cp = after_cp, winB = winB, winA = winA }
end

function Match:annotation(ply)
    if not self.g.annotations[ply] then self:_annotate(ply) end
    return self.g.annotations[ply]
end

-- Explanation of move number `ply`: { title, cat, text }; nil if impossible
function Match:explain(ply)
    local g = self.g
    if ply < 1 or ply > #g.moves then return nil end
    local pos = self.positions[ply]
    local m = pos:findUci(g.moves[ply])
    if not m then return nil end
    local num = pos.fullmove .. (pos.turn == "w" and ". " or "… ") .. self.sans[ply]
    if pos.turn ~= g.player_color then
        return { title = num, text = Coach.moveSentence(pos, m, "adversaire"), opponent = true }
    end
    local a = self:annotation(ply)
    if not a then
        local pending = self:isCoach() and not g.lines[pos:key()]
        return { title = num, text = Coach.moveSentence(pos, m, "joueur")
            .. (pending and "\nThe coach is still analysing this move…" or "") }
    end
    local posAfter = self.positions[ply + 1]
    local e = Coach.explain{
        pos = pos, move = m, cls = a.cls, before = g.lines[pos:key()],
        after_lines = g.lines[posAfter:key()], after_cp = a.after_cp,
    }
    return { title = num, cat = a.cls, text = table.concat(e.paragraphs, "\n"),
        best = g.lines[pos:key()] and g.lines[pos:key()][1] and g.lines[pos:key()][1].move }
end

-- Hint for the displayed position: discreet text, move, full explanation
function Match:hint()
    if not self:isCoach() then return nil end
    local pos = self:viewPos()
    if pos.turn ~= self.g.player_color or self:ended() then return nil end
    local lines = self.g.lines[pos:key()]
    if not lines then
        self:_requestLines(pos, 2)
        return nil, "pending"
    end
    local vague, full = Coach.hint(pos, lines)
    return vague, pos:findUci(lines[1].move), full
end

function Match:accuracy()
    local g = self.g
    local total, inv, wsum = 0, 0, 0
    for ply, a in pairs(g.annotations) do
        local before = self.positions[ply] and g.lines[self.positions[ply]:key()]
        if before and before[1] and a.after_cp then
            local wb = AI.winPercent(before[1].cp)
            local wa = AI.winPercent(a.after_cp)
            local acc = Coach.accuracy(wb, wa)
            local w = 0.05 + (wb * (100 - wb)) / 2500
            total = total + acc * w
            inv = inv + w / math.max(acc, 5)
            wsum = wsum + w
        end
    end
    if wsum == 0 then return nil end
    return (total / wsum + wsum / inv) / 2
end

function Match:categoryCounts()
    local counts = {}
    for _, a in pairs(self.g.annotations) do counts[a.cls] = (counts[a.cls] or 0) + 1 end
    return counts
end

---------------------------------------------------------------------------
-- Navigation
---------------------------------------------------------------------------

function Match:goTo(idx)
    if not self:canNavigate() then return false end
    local g = self.g
    idx = math.max(0, math.min(#g.moves, idx))
    if idx == g.cursor then return false end
    g.cursor = idx
    self:save()
    self.onUpdate("nav")
    if self:isCoach() and not self:ended() then
        if self:atEnd() and not self:playerToMove() and not self.thinking then
            self:_aiTurn()
        else
            self:_preAnalyseView()
        end
    end
    return true
end

function Match:step(dir) return self:goTo(self.g.cursor + dir) end
function Match:toEnd() return self:goTo(#self.g.moves) end

---------------------------------------------------------------------------
-- End of game
---------------------------------------------------------------------------

function Match:_finish(result, reason)
    local g = self.g
    if g.result then return end
    g.result = result
    g.reason = reason
    if result == "1/2-1/2" then g.score = 0.5
    elseif (result == "1-0") == (g.player_color == "w") then g.score = 1
    else g.score = 0 end
    self.thinking = false
    self.gen = self.gen + 1
    if self.engine then self.engine:cancelAll() end
    self.pending = {}
    -- a game is "rated" only once
    if not g.rated_done then
        g.rated_done = true
        self.onFinish(self)
    end
    self:save()
    self.onUpdate("gameover")
end

function Match:resign()
    if self:ended() then return end
    self:_accrue()
    self:_finish(self.g.player_color == "w" and "0-1" or "1-0", "resignation")
end

-- Draw offer: returns true (accepted), false (declined) or nil (not possible)
function Match:offerDraw()
    local g = self.g
    if self:ended() or self:isCoach() then return nil end
    if self.last_offer and #g.moves - self.last_offer < 6 then return nil end
    self.last_offer = #g.moves
    local pos = self:livePos()
    local cp
    for i = #g.moves, math.max(0, #g.moves - 3), -1 do
        cp = g.evals[self.positions[i + 1]:key()]
        if cp then break end
    end
    local aiCp = cp and (self:aiColor() == "w" and cp or -cp)
    local ratio
    if self:isTimed() then
        ratio = g.clock[self:aiColor()] / math.max(1, g.clock[g.player_color])
    end
    if AI.acceptsDraw(self:persona(), aiCp, pos.fullmove, ratio, self.rnd) then
        self:_accrue()
        self:_finish("1/2-1/2", "draw by agreement")
        return true
    end
    return false
end

function Match:resultText()
    local g = self.g
    if not g.result then return nil end
    local s
    if g.score == 1 then s = "Win" elseif g.score == 0 then s = "Loss" else s = "Draw" end
    return s .. " (" .. (g.reason or "") .. ")"
end

function Match:playerMovesCount()
    local n = 0
    for i = 1, #self.g.moves do
        if self.positions[i].turn == self.g.player_color then n = n + 1 end
    end
    return n
end

-- Evaluation curve (White's point of view), gaps filled by interpolation
function Match:evalSeries()
    local n = #self.g.moves
    local vals = {}
    for i = 0, n do vals[i] = self:evalAt(i) end
    vals[0] = vals[0] or 20
    local last = 0
    for i = 0, n do
        if vals[i] == nil then
            local j = i + 1
            while j <= n and vals[j] == nil do j = j + 1 end
            local nxt = (j <= n) and vals[j] or vals[last]
            for k = i, j - 1 do
                vals[k] = vals[last] + (nxt - vals[last]) * (k - last) / (j - last)
            end
        else
            last = i
        end
    end
    return vals, n
end

return Match
