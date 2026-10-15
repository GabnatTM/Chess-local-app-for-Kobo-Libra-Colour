--[[
  The conductor: saved data, opening screens,
  creating games, Elo rating, tournaments.
]]

local ButtonDialog = require("ui/widget/buttondialog")
local UIManager = require("ui/uimanager")

local AI = require("cc_ai")
local Career = require("cc_career")
local GameScreen = require("cc_screen")
local Match = require("cc_match")
local Menus = require("cc_menus")
local T = require("cc_tournament")

local App = {}
App.__index = App

local DEFAULT_PROFILE = {
    player_elo = 800, games_played = 0, ai_elo = 1200, style = "equilibre",
    think_ms = 1000, player_color = "w",
}

--[[
  opts = { engine, load() -> table, save(table), now() -> seconds (wall clock),
           clock() -> seconds (monotonic clock, for chess clocks),
           schedule(sec, fn), rnd }
]]
function App.new(opts)
    local self = setmetatable({}, App)
    self.engine = opts.engine
    self._save = opts.save
    self._now = opts.now or os.time
    self._clock = opts.clock or opts.now or os.time
    self.schedule = opts.schedule
    self.rnd = opts.rnd or math.random
    self.data = (opts.load and opts.load()) or {}
    self:_migrate()
    self.profile = self.data.profile
    self.career = Career.ensure(self.data, self.rnd)
    self.opened = {}
    return self
end

function App:now() return self._now() end
function App:save() if self._save then self._save(self.data) end end

function App:_migrate()
    local d = self.data
    d.profile = d.profile or {}
    for k, v in pairs(DEFAULT_PROFILE) do
        if d.profile[k] == nil then d.profile[k] = v end
    end
    d.history = d.history or {}
    -- old plugin version: a single "coach" game
    if d.game and not d.coach_game then
        local old = d.game
        local g = Match.newGame{
            mode = "coach", player_color = old.player_color or "w",
            opp = { id = "ia", name = "AI " .. (old.ai_elo or d.profile.ai_elo), elo = old.ai_elo or d.profile.ai_elo,
                style = old.style or d.profile.style, persona = "equilibre" },
        }
        g.start_fen = old.start_fen or g.start_fen
        g.moves = old.moves or {}
        g.cursor = #g.moves
        g.result, g.reason, g.rated_done = old.result, old.reason, old.rated
        if old.result then
            if old.result == "1/2-1/2" then g.score = 0.5
            elseif (old.result == "1-0") == (g.player_color == "w") then g.score = 1 else g.score = 0 end
        end
        d.coach_game = g
    end
    d.game = nil
    d.version = 2
end

---------------------------------------------------------------------------
-- Screens
---------------------------------------------------------------------------

function App:push(screen)
    self.opened[#self.opened + 1] = screen
    local prev = screen.onClose
    screen.onClose = function(sc)
        if prev then prev(sc) end
        for i = #self.opened, 1, -1 do
            if self.opened[i] == sc then table.remove(self.opened, i) end
        end
    end
    screen:show()
    return screen
end

function App:closeToMain()
    for i = #self.opened, 1, -1 do
        local sc = self.opened[i]
        if sc ~= self.main and not sc.closed then sc:close("none") end
    end
    -- full screen refresh (avoids ghosting on e-ink)
    if self.main and not self.main.closed then
        UIManager:setDirty(self.main, "full")
    end
end

function App:openMain()
    self.main = self:push(Menus.Main:new{ app = self })
end

function App:openHub() self:push(Menus.Hub:new{ app = self }) end
function App:openShelf() self:push(Menus.Shelf:new{ app = self }) end
function App:openProfile() self:push(Menus.Profile:new{ app = self }) end
function App:openFree() self:push(Menus.Free:new{ app = self }) end
function App:openTournament() self:push(Menus.Tournament:new{ app = self }) end

---------------------------------------------------------------------------
-- Games
---------------------------------------------------------------------------

function App:makeMatch(game)
    return Match.new{
        game = game, engine = self.engine, settings = self.profile, rnd = self.rnd,
        now = self._clock, schedule = self.schedule,
        save = function() self:save() end,
        onFinish = function(match) self:onGameFinished(match) end,
    }
end

-- ctx = { exit_label, newGame = fn, tournament = bool }
function App:openGame(game, ctx)
    ctx = ctx or {}
    local match = self:makeMatch(game)
    local screen
    local actions = {
        profile = self.profile,
        exit_label = ctx.exit_label,
        exit = function() screen:close("full") end,
        newGame = ctx.newGame,
        archive = ctx.archive or (game.mode == "coach" and function() self:openArchive() end) or nil,
        bilan = function() self:openBilan(match, screen, ctx) end,
    }
    screen = GameScreen:new{ match = match, actions = actions }
    self:push(screen)
    self.game_screen = screen
    match:resume()
    return screen
end

function App:openBilan(match, screen, ctx)
    if self.bilan and not self.bilan.closed then return end
    local bilan
    local actions = {
        review = function(idx)
            bilan:close()
            if idx then match:goTo(idx) end
            screen:refresh("ui")
        end,
        menu = function()
            bilan:close()
            self:closeToMain()
        end,
        closed = function()
            match.onUpdate = function(ev) screen:onMatchUpdate(ev) end
        end,
    }
    if not match:isCoach() and match.g.archive_id then
        actions.analyse = function()
            local entry = self:archiveEntry(match.g.archive_id)
            bilan:close("none")
            screen:close("none")
            self:analyseArchived(entry)
        end
    end
    if ctx.tournament then
        actions.continue = function()
            bilan:close()
            screen:close()
        end
        actions.continue_label = "Back to tournament"
    elseif ctx.newGame then
        actions.newGame = function()
            bilan:close()
            screen:close()
            ctx.newGame()
        end
    end
    bilan = Menus.Bilan:new{ app = self, match = match, actions = actions }
    self.bilan = bilan
    self:push(bilan)
end

---------------------------------------------------------------------------
-- Coach
---------------------------------------------------------------------------

function App:coachOpp()
    local p = self.profile
    return { id = "ia", name = "AI " .. p.ai_elo, elo = p.ai_elo, style = p.style, persona = "equilibre" }
end

function App:openCoach()
    local d = self.data
    if not d.coach_game then
        d.coach_game = Match.newGame{ mode = "coach", player_color = self.profile.player_color, opp = self:coachOpp() }
        self:save()
    end
    self:openGame(d.coach_game, { newGame = function() self:newCoachGame() end })
end

function App:openArchive()
    self:push(Menus.Archive:new{ app = self })
end

function App:archiveEntry(id)
    for _, e in ipairs(self.data.archive or {}) do
        if e.id == id then return e end
    end
end

function App.scoreText(result)
    if result == "1/2-1/2" then return "½-½" end
    return result or "*"
end

-- Opens an archived game in the coach for analysis
function App:analyseArchived(entry)
    if not entry then return end
    local g = Match.newGame{
        mode = "coach", player_color = entry.player_color, start_fen = entry.start_fen,
        opp = { id = "ia", name = entry.opp.name, elo = self.profile.ai_elo, style = self.profile.style, persona = "equilibre" },
        label = "Analysis — " .. entry.white .. " – " .. entry.black,
    }
    for i, u in ipairs(entry.moves) do g.moves[i] = u end
    g.cursor = 0
    g.result, g.reason, g.score = entry.result, entry.reason, entry.score
    g.rated_done = true
    g.analysis = true
    g.label_short = entry.white .. " – " .. entry.black
    g.score_text = App.scoreText(entry.result)
    self.data.analysis_game = g
    self:save()
    local screen = self:openGame(g, {
        exit_label = "Back",
        newGame = function() self:newCoachGame() end,
        archive = function() self:openArchive() end,
    })
    screen.match:analyseForCoach()
end

function App:newCoachGame()
    local dialog
    local function start(color)
        if color == "aleatoire" then color = self.rnd() < 0.5 and "w" or "b" end
        self.profile.player_color = color
        if self.game_screen and not self.game_screen.closed then self.game_screen:close() end
        self.data.coach_game = Match.newGame{ mode = "coach", player_color = color, opp = self:coachOpp() }
        self:save()
        self:openCoach()
    end
    local function item(text, color)
        return { text = text, callback = function()
            UIManager:close(dialog)
            start(color)
        end }
    end
    dialog = ButtonDialog:new{
        title = "New game against AI " .. self.profile.ai_elo .. " (" .. AI.styleById(self.profile.style).name .. ")",
        buttons = { { item("White", "w"), item("Black", "b") }, { item("Random", "aleatoire") } },
    }
    UIManager:show(dialog)
end

---------------------------------------------------------------------------
-- Casual game
---------------------------------------------------------------------------

local CADENCES = {
    blitz = { tc = { base = 180, inc = 5 }, label = "Casual game — blitz 3 + 5" },
    rapide = { tc = { base = 600, inc = 5 }, label = "Casual game — rapid 10 + 5" },
    sans = { tc = nil, label = "Casual game — no clock" },
}

function App:pickOpponent(target)
    local cands = {}
    for _, p in ipairs(self.career.pool) do cands[#cands + 1] = p end
    table.sort(cands, function(a, b) return math.abs(a.elo - target) < math.abs(b.elo - target) end)
    return cands[math.floor(self.rnd() * math.min(12, #cands)) + 1]
end

function App:startFree(cadence, color)
    local d = self.data
    local fg = d.free_game
    if fg and not fg.result and #fg.moves >= 2 then
        local mm = self:makeMatch(fg)
        mm:resign()
    end
    if color == "aleatoire" then color = self.rnd() < 0.5 and "w" or "b" end
    local npc = self:pickOpponent(self.profile.player_elo)
    local c = CADENCES[cadence] or CADENCES.rapide
    d.free_game = Match.newGame{
        mode = "libre", player_color = color, tc = c.tc, label = c.label,
        opp = { id = npc.id, name = npc.name, elo = npc.elo, persona = npc.persona, style = AI.persona(npc.persona).style },
    }
    self:save()
    self:resumeFree()
end

function App:resumeFree()
    self:openGame(self.data.free_game, {
        exit_label = "Back",
        newGame = function() self:openFree() end,
    })
end

---------------------------------------------------------------------------
-- Tournaments
---------------------------------------------------------------------------

function App:me() return { name = "You", elo = self.profile.player_elo } end

function App:startOpen(cityId)
    local t = Career.startOpen(self.career, cityId, self:me(), self:now(), self.rnd)
    self:save()
    return t
end

function App:startCandidates()
    local t = Career.startCandidates(self.career, self:me(), self:now(), self.rnd)
    self:save()
    return t
end

function App:startWorld()
    local t = Career.startWorld(self.career, self:me(), self:now(), self.rnd)
    self:save()
    return t
end

function App:abandonTournament()
    local s = self.career.season
    s.active = nil
    self:save()
end

function App:newSeason()
    Career.newSeason(self.career, self.rnd)
    self:save()
end

local KIND_MODE = { open = "tournoi", candidats = "candidats", monde = "monde" }

function App:playTournamentRound()
    local t = self.career.season.active
    if not t or t.finished then return end
    T.pairRound(t, self.rnd)
    if not t.game then
        local _, color, oi = T.myPairing(t)
        local opp = t.players[oi]
        local label
        if t.kind == "monde" then
            label = t.name .. (t.round > t.rounds and " — tiebreak" or (" — game " .. t.round))
        else
            label = t.name .. " — round " .. t.round
        end
        t.game = Match.newGame{
            mode = KIND_MODE[t.kind], player_color = color, tc = T.tcForRound(t), label = label,
            opp = { id = opp.id, name = opp.name, elo = opp.elo, persona = opp.persona,
                style = AI.persona(opp.persona).style },
        }
        self:save()
    end
    self:openGame(t.game, { exit_label = "Back to tournament", tournament = true })
end

---------------------------------------------------------------------------
-- End of a game: Elo, history, tournament
---------------------------------------------------------------------------

function App:onGameFinished(match)
    local g = match.g
    local p = self.profile
    local rated
    if g.mode == "coach" then
        rated = not g.takeback and match:playerMovesCount() >= 2
    elseif g.mode == "libre" then
        rated = match:playerMovesCount() >= 2
    else
        rated = true
    end
    if rated then
        local old = p.player_elo
        local new = AI.updateRating(old, g.opp.elo, g.score, p.games_played)
        p.player_elo = new
        p.games_played = p.games_played + 1
        g.elo_before, g.elo_after = old, new
    end
    local acc = match:isCoach() and match:accuracy() or nil
    local h = self.data.history
    h[#h + 1] = {
        date = os.date("%Y-%m-%d %H:%M"), mode = g.mode, label = g.label,
        opp = g.opp.name, opp_elo = g.opp.elo, result = g.result, reason = g.reason, score = g.score,
        color = g.player_color, moves = #g.moves, elo_before = g.elo_before, elo_after = g.elo_after,
        accuracy = acc and math.floor(acc + 0.5) or nil,
    }
    while #h > 300 do table.remove(h, 1) end

    -- archive the game (to analyse it later with the coach)
    if not g.analysis then
        local d = self.data
        d.archive = d.archive or {}
        d.archive_next = (d.archive_next or 0) + 1
        local you, opp = "You", g.opp.name
        local moves = {}
        for i, u in ipairs(g.moves) do moves[i] = u end
        local entry = {
            id = d.archive_next, time = os.time(), mode = g.mode, label = g.label,
            white = g.player_color == "w" and you or opp, black = g.player_color == "w" and opp or you,
            result = g.result, reason = g.reason, score = g.score, moves = moves, start_fen = g.start_fen,
            player_color = g.player_color, opp = { name = g.opp.name, elo = g.opp.elo, persona = g.opp.persona },
        }
        d.archive[#d.archive + 1] = entry
        while #d.archive > 150 do table.remove(d.archive, 1) end
        g.archive_id = entry.id
    end

    if KIND_MODE.open == g.mode or g.mode == "candidats" or g.mode == "monde" then
        local s = self.career.season
        local t = s.active
        if t and t.game == g then
            T.recordResult(t, g.result, Career.poolById(self.career), self.rnd)
            t.game = nil
            if t.finished then
                Career.onTournamentFinished(self.career, t, self:now())
                s.last_tournament = t
            end
        end
    end
    self:save()
end

return App
