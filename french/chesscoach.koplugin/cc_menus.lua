--[[
  Les écrans du jeu : menu principal, circuit des capitales,
  tournoi, étagère des trophées, partie libre, profil, bilan de partie.
]]

local ConfirmBox = require("ui/widget/confirmbox")
local InfoMessage = require("ui/widget/infomessage")
local SpinWidget = require("ui/widget/spinwidget")
local TextViewer = require("ui/widget/textviewer")
local UIManager = require("ui/uimanager")

local AI = require("cc_ai")
local Art = require("cc_art")
local Career = require("cc_career")
local Coach = require("cc_coach")
local Draw = require("cc_draw")
local T = require("cc_tournament")
local UI = require("cc_ui")

local s = UI.s
local Menus = {}

local function plural(n, a, b) return n .. " " .. ((n > 1 or n == 0) and (b or (a .. "s")) or a) end

local function fmtPts(p)
    if p == math.floor(p) then return tostring(math.floor(p)) end
    return (math.floor(p) > 0 and tostring(math.floor(p)) or "") .. "½"
end
Menus.fmtPts = fmtPts

local function resLabel(res)
    if res == "1/2-1/2" then return "½ – ½" end
    if res == "1-0" then return "1 – 0" end
    if res == "0-1" then return "0 – 1" end
    return "…"
end

---------------------------------------------------------------------------
-- Graphique d'évaluation (blanc vers le haut, noir vers le bas)
---------------------------------------------------------------------------

function Menus.drawEvalGraph(bb, x, y, w, h, vals, n, marks)
    bb:paintRect(x, y, w, h, UI.MID)
    local mid = y + math.floor(h / 2)
    local function yOf(cp)
        local win = AI.winPercent(cp) / 100 -- 0..1
        return y + h - win * h
    end
    if n <= 0 then
        bb:paintRect(x, mid, w, 1, UI.DIM)
        bb:paintBorder(x, y, w, h, 1, UI.BLACK)
        return function() return nil end
    end
    local function xOf(i) return x + (w - 1) * i / n end
    for px = 0, w - 1 do
        local fi = px / (w - 1) * n
        local i0 = math.floor(fi)
        local i1 = math.min(n, i0 + 1)
        local f = fi - i0
        local cp = vals[i0] + ((vals[i1] or vals[i0]) - vals[i0]) * f
        local yy = math.floor(yOf(cp) + 0.5)
        if yy < mid then
            bb:paintRect(x + px, yy, 1, mid - yy, UI.WHITE)
        elseif yy > mid then
            bb:paintRect(x + px, mid, 1, yy - mid, UI.BLACK)
        end
    end
    bb:paintRect(x, mid, w, 1, UI.DIM)
    for _, mk in ipairs(marks or {}) do
        local cx = math.floor(xOf(mk.idx))
        local cy = math.floor(yOf(vals[mk.idx] or 0))
        Draw.disc(bb, cx, cy, s(6), nil, 0x00)
        Draw.disc(bb, cx, cy, s(5), mk.color, mk.gray)
    end
    bb:paintBorder(x, y, w, h, 1, UI.BLACK)
    return function(px)
        local i = math.floor((px - x) / (w - 1) * n + 0.5)
        return math.max(0, math.min(n, i))
    end
end

---------------------------------------------------------------------------
-- Menu principal
---------------------------------------------------------------------------

Menus.Main = UI.Canvas:extend{ app = nil }

function Menus.Main:draw(bb)
    local app = self.app
    local W = self.W
    local p = app.profile
    local season = app.career.season
    local y = s(20)
    -- titre
    local knight = UI.pieceFace(s(110))
    Draw.glyphCentered(bb, knight, 0x265E, W / 2, y + s(60), UI.BLACK)
    y = y + s(128)
    UI.textCentered(bb, UI.face(34, true), "Le Circuit", W / 2, y)
    y = y + UI.lineHeight(UI.face(34, true))
    UI.textCentered(bb, UI.face(15), "Échecs · coach · tournois", W / 2, y, UI.DIM)
    y = y + s(34)

    -- carte joueur
    local cw = math.floor(W * 0.8)
    local cx = math.floor((W - cw) / 2)
    local ch = s(58)
    Draw.roundedRect(bb, cx, y, cw, ch, s(12), nil, 0xEE)
    local f = UI.face(16, true)
    UI.text(bb, f, "Votre Elo : " .. p.player_elo, cx + s(16), y + s(8))
    local trophies = Career.trophyCount(season)
    local info = "Saison " .. season.n .. " · " .. trophies .. "/10 trophées"
    local d = Career.day(season, app:now())
    if d then
        local left = Career.TOURNAMENT_DAYS - d
        if left > 0 then info = info .. " · " .. plural(math.ceil(left / Career.MONTH_DAYS), "mois", "mois") .. " restants" end
    end
    UI.text(bb, UI.face(14), info, cx + s(16), y + s(32), UI.DIM)
    y = y + ch + s(26)

    local entries = {
        { "Tournois", "Le circuit des 10 capitales", function() app:openHub() end, Art.iconBuilding },
        { "Coach", "Jouez ou analysez vos parties avec le coach", function() app:openCoach() end, Art.iconBulb },
        { "Partie libre", "Blitz, rapide ou sans pendule", function() app:openFree() end, Art.iconClock },
        { "Trophées", "Votre étagère", function() app:openShelf() end, function(b, x, yy, sz)
            Art.trophy(b, x, yy, sz, sz, UI.GOLD, false) end },
        { "Profil", "Classement et historique", function() app:openProfile() end, Art.iconChart },
    }
    local rowh = s(70)
    local rx, rw = cx, cw
    for i, e in ipairs(entries) do
        local ry = y + (i - 1) * rowh
        local isz = s(40)
        e[4](bb, rx + s(8), ry + (rowh - isz) / 2, isz)
        UI.text(bb, UI.face(20, true), e[1], rx + s(66), ry + s(10))
        UI.text(bb, UI.face(14), e[2], rx + s(66), ry + s(40), UI.DIM)
        UI.textRight(bb, UI.face(22), "›", rx + rw - s(8), ry + s(18), UI.GRAY)
        if i < #entries then bb:paintRect(rx + s(66), ry + rowh - 1, rw - s(66), 1, UI.LIGHT) end
        self:region(rx, ry, rw, rowh, e[3])
    end
    y = y + #entries * rowh + s(20)
    local qf = UI.face(15)
    local qw = UI.textWidth(qf, "Quitter") + s(40)
    UI.pill(bb, (W - qw) / 2, y, qw, s(34), "Quitter", qf)
    self:region((W - qw) / 2, y, qw, s(34), function() self:close() end)
end

---------------------------------------------------------------------------
-- Circuit des capitales
---------------------------------------------------------------------------

Menus.Hub = UI.Canvas:extend{ app = nil }

local OPEN_STATUS = {
    gagne = "Trophée gagné", en_cours = "En cours", ouvert = "Ouvert", bloque = "Ouvert", ferme = "Fermé",
}

function Menus.Hub:draw(bb)
    local app = self.app
    local W = self.W
    local now = app:now()
    local season = app.career.season
    local y = self:header(bb, "Circuit des capitales", "Menu", function() self:close() end)
    local m = s(14)
    y = y + s(8)
    UI.text(bb, UI.face(18, true), "Saison " .. season.n .. " — " .. Career.trophyCount(season) .. " / 10 trophées", m, y)
    y = y + UI.lineHeight(UI.face(18, true))
    for _, l in ipairs(UI.wrap(UI.face(15), Career.countdownText(season, now), W - 2 * m)) do
        UI.text(bb, UI.face(15), l, m, y, UI.DIM)
        y = y + UI.lineHeight(UI.face(15))
    end
    y = y + s(10)

    -- les 10 villes
    local cols = 5
    local gap = s(8)
    local cw = math.floor((W - 2 * m - (cols - 1) * gap) / cols)
    local ch = s(178)
    for i, c in ipairs(T.CITIES) do
        local col = (i - 1) % cols
        local row = math.floor((i - 1) / cols)
        local x = m + col * (cw + gap)
        local yy = y + row * (ch + gap)
        local st = Career.openStatus(app.career, c.id, now)
        if st == "gagne" then
            Draw.roundedRect(bb, x, yy, cw, ch, s(10), c.color, 0xE0)
        elseif st == "en_cours" then
            bb:paintBorder(x, yy, cw, ch, s(2), UI.BLACK, s(10))
        end
        local ah = math.floor(ch * 0.62)
        local gray = (st == "ferme") and 0xB8 or 0x22
        Art.building(bb, c.art, x + cw * 0.12, yy + s(8), cw * 0.76, ah, gray)
        if st == "gagne" then
            Art.cityTrophy(bb, c.id, x + cw - s(32), yy + s(4), s(28), s(32), UI.GOLD, false)
        end
        UI.textCentered(bb, UI.face(15, true), c.name, x + cw / 2, yy + ah + s(12))
        local sub = OPEN_STATUS[st] or ""
        if st == "en_cours" and season.active then sub = "Ronde " .. math.min(season.active.round, season.active.rounds) .. " / 6" end
        if (st == "ouvert" or st == "bloque") and (season.attempts[c.id] or 0) > 0 then
            sub = "Nouvel essai"
        end
        UI.textCentered(bb, UI.face(12), sub, x + cw / 2, yy + ah + s(12) + UI.lineHeight(UI.face(15, true)),
            st == "ferme" and UI.LIGHT or UI.DIM)
        self:region(x, yy, cw, ch, function() self:tapCity(c, st) end)
    end
    y = y + 2 * (ch + gap) + s(8)

    -- tournoi des candidats
    local bw = W - 2 * m
    local bh = s(92)
    local cst = Career.candidatesStatus(app.career, now)
    local locked = cst == "verrouille" or cst == "ferme"
    bb:paintBorder(m, y, bw, bh, s(1), locked and UI.LIGHT or UI.BLACK, s(12))
    Art.ticket(bb, m + s(12), y + s(14), s(90), bh - s(28), UI.GOLD, not season.candidates.won)
    local tx = m + s(118)
    UI.text(bb, UI.face(18, true), "Tournoi des candidats", tx, y + s(10), locked and UI.GRAY or UI.BLACK)
    local ctext
    if cst == "verrouille" then
        ctext = "Gagnez les 10 tournois en 10 mois pour y accéder. 6 rondes, cadence 15 + 10, adversaires un peu plus forts."
    elseif cst == "ferme" then
        ctext = "Le tournoi des candidats est terminé pour cette saison."
    elseif cst == "gagne" then
        ctext = "Gagné ! Vous avez votre ticket pour le championnat du monde."
    elseif cst == "en_cours" then
        ctext = "En cours — ronde " .. math.min(season.active.round, 6) .. " / 6."
    else
        ctext = "Ouvert jusqu'au championnat du monde, autant d'essais que vous voulez. Essais : " .. (season.candidates.attempts or 0)
    end
    local ly = y + s(10) + UI.lineHeight(UI.face(18, true))
    for _, l in ipairs(UI.wrap(UI.face(13), ctext, bw - s(130))) do
        UI.text(bb, UI.face(13), l, tx, ly, UI.DIM)
        ly = ly + UI.lineHeight(UI.face(13))
    end
    self:region(m, y, bw, bh, function() self:tapCandidates(cst) end)
    y = y + bh + s(10)

    -- championnat du monde
    local wst = Career.worldStatus(app.career, now)
    bb:paintBorder(m, y, bw, bh, s(1), UI.BLACK, s(12))
    Art.crown(bb, m + s(20), y + s(16), s(76), bh - s(32), UI.GOLD, not (season.wc and season.wc.me_won))
    UI.text(bb, UI.face(18, true), "Championnat du monde", tx, y + s(10))
    local champ = Career.npc(app.career, season.champion_id)
    local wtext
    if wst == "a_venir" then
        local dd = Career.daysToWorld(season, now)
        wtext = "Champion en titre : " .. champ.name .. ". "
            .. (dd and ("Dans " .. plural(dd, "jour") .. ". ") or "Au 364e jour de la saison. ")
            .. "Match en 13 parties, cadence 15 + 10."
    elseif wst == "qualifie" then
        wtext = "C'est le moment ! Votre match en 13 parties contre " .. champ.name .. " vous attend."
    elseif wst == "spectateur" then
        wtext = "Le match oppose " .. champ.name .. " au vainqueur des candidats. Touchez pour suivre le résultat."
    else
        local wc = season.wc
        if wc.simulated then
            wtext = wc.new_champion .. " est champion du monde (" .. fmtPts(wc.match.pa) .. " – " .. fmtPts(wc.match.pb) .. "). Touchez pour une nouvelle saison."
        elseif wc.me_won then
            wtext = "Vous êtes champion du monde ! Touchez pour une nouvelle saison."
        else
            wtext = champ.name .. " conserve son titre. Touchez pour une nouvelle saison."
        end
    end
    ly = y + s(10) + UI.lineHeight(UI.face(18, true))
    for _, l in ipairs(UI.wrap(UI.face(13), wtext, bw - s(130))) do
        UI.text(bb, UI.face(13), l, tx, ly, UI.DIM)
        ly = ly + UI.lineHeight(UI.face(13))
    end
    self:region(m, y, bw, bh, function() self:tapWorld(wst) end)
    y = y + bh + s(14)

    local f = UI.face(15)
    local lw = UI.textWidth(f, "Étagère des trophées ›")
    UI.text(bb, f, "Étagère des trophées ›", (W - lw) / 2, y)
    self:region((W - lw) / 2 - s(20), y - s(6), lw + s(40), UI.lineHeight(f) + s(12), function() app:openShelf() end)
end

function Menus.Hub:tapCity(c, st)
    local app = self.app
    local season = app.career.season
    if st == "en_cours" then
        app:openTournament()
    elseif st == "gagne" then
        local tr = season.trophies[c.id]
        UIManager:show(InfoMessage:new{ text = "Vous avez gagné l'Open de " .. c.name .. " (jour " .. (tr.day or 0) + 1 .. " de la saison).", timeout = 3 })
    elseif st == "bloque" then
        UIManager:show(InfoMessage:new{ text = "Terminez d'abord le tournoi en cours : " .. season.active.name .. ".", timeout = 3 })
    elseif st == "ferme" then
        UIManager:show(InfoMessage:new{ text = "La saison des tournois est terminée.", timeout = 3 })
    else
        local first = not season.start
        UIManager:show(ConfirmBox:new{
            text = "Participer à l'Open de " .. c.name .. " ?\n\n8 joueurs, 6 rondes, cadence 10 + 5.\nVictoire = 1 point, nulle = ½, défaite = 0."
                .. (first and "\n\nC'est votre premier tournoi : le compte à rebours de 10 mois démarre maintenant !" or ""),
            ok_text = "C'est parti", cancel_text = "Plus tard",
            ok_callback = function()
                if app:startOpen(c.id) then
                    self:refresh()
                    app:openTournament()
                end
            end,
        })
    end
end

function Menus.Hub:tapCandidates(cst)
    local app = self.app
    if cst == "en_cours" then app:openTournament()
    elseif cst == "ouvert" then
        UIManager:show(ConfirmBox:new{
            text = "Participer au tournoi des candidats ?\n\n8 joueurs, 6 rondes, cadence 15 + 10.\nLe vainqueur affronte le champion du monde.",
            ok_text = "C'est parti", cancel_text = "Plus tard",
            ok_callback = function()
                if app:startCandidates() then app:openTournament() end
            end,
        })
    elseif cst == "bloque" then
        UIManager:show(InfoMessage:new{ text = "Terminez d'abord le tournoi en cours.", timeout = 3 })
    else
        UIManager:show(InfoMessage:new{ text = cst == "gagne" and "Vous êtes qualifié pour le championnat du monde !"
            or "Gagnez les 10 tournois du circuit en 10 mois pour débloquer le tournoi des candidats.", timeout = 3 })
    end
end

function Menus.Hub:tapWorld(wst)
    local app = self.app
    if wst == "qualifie" then
        app:startWorld()
        app:openTournament()
    elseif wst == "spectateur" then
        local wc = Career.simulateWorld(app.career, { elo = app.profile.player_elo }, app.rnd)
        app:save()
        local lines = { wc.champion .. " (champion en titre) contre " .. wc.candidate .. " (vainqueur des candidats)", "" }
        for i, gm in ipairs(wc.match.games) do
            lines[#lines + 1] = "Partie " .. i .. " : " .. gm.white .. " – " .. gm.black .. "   " .. resLabel(gm.res)
        end
        lines[#lines + 1] = ""
        lines[#lines + 1] = "Score final : " .. fmtPts(wc.match.pa) .. " – " .. fmtPts(wc.match.pb)
        lines[#lines + 1] = wc.new_champion .. " est champion du monde."
        UIManager:show(TextViewer:new{ title = "Championnat du monde", text = table.concat(lines, "\n") })
        self:refresh()
    elseif wst == "termine" then
        UIManager:show(ConfirmBox:new{
            text = "Commencer une nouvelle saison ?\n\nVos trophées de cette saison restent dans votre palmarès ; un nouveau circuit de 10 tournois commence.",
            ok_text = "Nouvelle saison", cancel_text = "Plus tard",
            ok_callback = function()
                app:newSeason()
                self:refresh("flashui")
            end,
        })
    else
        UIManager:show(InfoMessage:new{ text = "Le championnat du monde aura lieu au 364e jour de la saison.", timeout = 3 })
    end
end

---------------------------------------------------------------------------
-- Tournoi
---------------------------------------------------------------------------

Menus.Tournament = UI.Canvas:extend{ app = nil }

function Menus.Tournament:draw(bb)
    local app = self.app
    local season = app.career.season
    local t = season.active or season.last_tournament
    local W = self.W
    local m = s(14)
    if not t then
        self:header(bb, "Tournoi", "Circuit", function() self:close() end)
        UI.text(bb, UI.face(16), "Aucun tournoi en cours.", m, s(60))
        return
    end
    local y = self:header(bb, t.name, "Circuit", function() self:close() end)
    y = y + s(8)
    local city = t.city and T.city(t.city)
    local artW = s(70)
    if city then
        Art.building(bb, city.art, m, y, artW, s(70), 0x22)
    elseif t.kind == "monde" then
        Art.crown(bb, m, y + s(8), artW, s(54), UI.GOLD, false)
    else
        Art.ticket(bb, m, y, artW, s(70), UI.GOLD, false)
    end
    local tx = m + artW + s(14)
    local tc = T.tcForRound(t)
    local roundTxt
    if t.finished then roundTxt = "Tournoi terminé"
    elseif t.kind == "monde" and t.round > t.rounds then roundTxt = "Partie de départage (blitz)"
    else roundTxt = (t.kind == "monde" and "Partie " or "Ronde ") .. t.round .. " / " .. t.rounds end
    UI.text(bb, UI.face(20, true), roundTxt, tx, y + s(4))
    UI.text(bb, UI.face(14), "Cadence " .. math.floor(tc.base / 60) .. " + " .. tc.inc .. "   ·   victoire 1, nulle ½, défaite 0",
        tx, y + s(36), UI.DIM)
    y = y + s(84)

    -- classement
    local rows = T.standings(t)
    local f, fb = UI.face(15), UI.face(15, true)
    local rh = s(30)
    UI.text(bb, UI.face(13), t.kind == "monde" and "Score du match" or "Classement", m, y, UI.GRAY)
    UI.textRight(bb, UI.face(13), "Points", W - m, y, UI.GRAY)
    y = y + UI.lineHeight(UI.face(13))
    for _, r in ipairs(rows) do
        local pl = r.player
        if pl.me then Draw.roundedRect(bb, m - s(6), y, W - 2 * m + s(12), rh, s(8), UI.SAND, 0xE4) end
        local ty = y + (rh - UI.lineHeight(f)) / 2 + s(2)
        UI.text(bb, f, r.rank .. ".", m, ty, UI.DIM)
        local nw = UI.text(bb, pl.me and fb or f, pl.me and "Vous" or pl.name, m + s(30), ty)
        local info = pl.elo .. (pl.persona and (" · " .. AI.persona(pl.persona).name) or "")
        if pl.champion then info = info .. " · champion du monde" end
        UI.text(bb, UI.face(13), "  " .. info, m + s(30) + nw, ty + s(2), UI.GRAY)
        UI.textRight(bb, fb, fmtPts(r.pts), W - m, ty)
        y = y + rh
    end
    y = y + s(14)

    if t.finished then
        local won = t.winner == 1
        local msg
        if t.kind == "monde" then
            local pts = T.points(t)
            msg = won and ("Vous êtes champion du monde ! (" .. fmtPts(pts[1]) .. " – " .. fmtPts(pts[2]) .. ")")
                or (t.players[2].name .. " conserve son titre (" .. fmtPts(pts[2]) .. " – " .. fmtPts(pts[1]) .. ").")
        elseif won then
            msg = (t.kind == "open") and "Vous remportez le tournoi ! Le trophée rejoint votre étagère."
                or "Vous gagnez le tournoi des candidats ! Rendez-vous au championnat du monde."
        else
            local rank
            for _, r in ipairs(rows) do if r.player.me then rank = r.rank end end
            msg = "Vous terminez " .. rank .. (rank == 1 and "er" or "e") .. ". "
                .. ((t.kind == "open") and "Vous pouvez retenter ce tournoi depuis le circuit." or "")
        end
        if won then
            if t.kind == "monde" then Art.crown(bb, (W - s(120)) / 2, y, s(120), s(96), UI.GOLD, false)
            elseif t.city then Art.cityTrophy(bb, t.city, (W - s(100)) / 2, y, s(100), s(110), UI.GOLD, false)
            else Art.ticket(bb, (W - s(140)) / 2, y, s(140), s(110), UI.GOLD, false) end
            y = y + s(116)
        end
        for _, l in ipairs(UI.wrap(UI.face(17, true), msg, W - 2 * m)) do
            UI.textCentered(bb, UI.face(17, true), l, W / 2, y)
            y = y + UI.lineHeight(UI.face(17, true))
        end
        y = y + s(12)
        local bw = s(220)
        UI.pill(bb, (W - bw) / 2, y, bw, s(40), "Retour au circuit", UI.face(16), { gray = 0xE8 })
        self:region((W - bw) / 2, y, bw, s(40), function()
            season.last_tournament = nil
            app:save()
            self:close()
        end)
        return
    end

    -- votre prochaine partie
    if not t.pairings[t.round] then
        T.pairRound(t, app.rnd)
        app:save()
    end
    local _, color, oi = T.myPairing(t)
    local opp = t.players[oi]
    local persona = AI.persona(opp.persona)
    local bh = s(150)
    bb:paintBorder(m, y, W - 2 * m, bh, s(1), UI.BLACK, s(12))
    local iy = y + s(10)
    UI.text(bb, UI.face(13), "Votre prochaine partie", m + s(14), iy, UI.GRAY)
    iy = iy + UI.lineHeight(UI.face(13))
    UI.text(bb, UI.face(19, true), opp.name .. "  ·  " .. opp.elo, m + s(14), iy)
    iy = iy + UI.lineHeight(UI.face(19, true))
    local desc = "Vous avez les " .. (color == "w" and "blancs" or "noirs") .. ". " .. persona.name .. " : " .. persona.desc
    for _, l in ipairs(UI.wrap(UI.face(14), desc, W - 2 * m - s(28))) do
        UI.text(bb, UI.face(14), l, m + s(14), iy, UI.DIM)
        iy = iy + UI.lineHeight(UI.face(14))
    end
    local label = t.game and "Reprendre la partie" or ("Jouer " .. (t.kind == "monde" and "la partie " or "la ronde ") .. t.round)
    local bw = UI.textWidth(UI.face(16, true), label) + s(40)
    UI.pill(bb, W - m - s(14) - bw, y + bh - s(52), bw, s(40), label, UI.face(16, true), { dark = true })
    self:region(m, y, W - 2 * m, bh, function() app:playTournamentRound() end)
    y = y + bh + s(14)

    -- résultats de la ronde précédente
    local prev = t.pairings[t.round - 1]
    if prev then
        UI.text(bb, UI.face(13), (t.kind == "monde" and "Partie " or "Ronde ") .. (t.round - 1) .. " — résultats", m, y, UI.GRAY)
        y = y + UI.lineHeight(UI.face(13))
        for _, q in ipairs(prev) do
            local wn = t.players[q.w].me and "Vous" or t.players[q.w].name
            local bn = t.players[q.b].me and "Vous" or t.players[q.b].name
            local ty = y
            UI.textRight(bb, UI.face(14), wn, W / 2 - s(40), ty)
            UI.textCentered(bb, UI.face(14, true), resLabel(q.res), W / 2, ty)
            UI.text(bb, UI.face(14), bn, W / 2 + s(40), ty)
            y = y + UI.lineHeight(UI.face(14))
            if y > self.H - s(60) then break end
        end
    end

    -- abandon du tournoi (pas pour le championnat du monde)
    if t.kind == "monde" then return end
    local f2 = UI.face(13)
    local q = "Abandonner le tournoi"
    local qw = UI.textWidth(f2, q)
    UI.text(bb, f2, q, (W - qw) / 2, self.H - s(30), UI.GRAY)
    self:region((W - qw) / 2 - s(10), self.H - s(40), qw + s(20), s(40), function()
        UIManager:show(ConfirmBox:new{
            text = "Abandonner ce tournoi ? Il ne comptera pas pour le trophée.",
            ok_text = "Abandonner", cancel_text = "Continuer",
            ok_callback = function()
                app:abandonTournament()
                self:close()
            end,
        })
    end)
end

---------------------------------------------------------------------------
-- Étagère des trophées
---------------------------------------------------------------------------

Menus.Shelf = UI.Canvas:extend{ app = nil }

function Menus.Shelf:draw(bb)
    local app = self.app
    local season = app.career.season
    local W = self.W
    local m = s(14)
    local y = self:header(bb, "Étagère des trophées — saison " .. season.n, "Retour", function() self:close() end)
    y = y + s(14)
    local cols = 5
    local cw = math.floor((W - 2 * m) / cols)
    local shelfH = s(190)
    for row = 0, 1 do
        local yy = y + row * shelfH
        for col = 0, cols - 1 do
            local c = T.CITIES[row * cols + col + 1]
            local won = season.trophies[c.id] ~= nil
            local x = m + col * cw
            Art.cityTrophy(bb, c.id, x + cw * 0.18, yy + s(6), cw * 0.64, s(130), UI.GOLD, not won)
            UI.textCentered(bb, UI.face(13, won), c.name, x + cw / 2, yy + s(150), won and UI.BLACK or UI.LIGHT)
        end
        -- planche
        Draw.rect(bb, m - s(4), yy + s(138), W - 2 * m + s(8), s(9), { 214, 190, 150 }, 0xA0)
    end
    y = y + 2 * shelfH + s(10)
    -- récompenses spéciales
    local half = math.floor((W - 2 * m) / 2)
    Art.ticket(bb, m + half * 0.2, y, half * 0.6, s(120), UI.GOLD, not season.candidates.won)
    UI.textCentered(bb, UI.face(13, season.candidates.won), "Ticket des candidats", m + half / 2, y + s(126),
        season.candidates.won and UI.BLACK or UI.LIGHT)
    local champ = season.wc and season.wc.me_won
    Art.crown(bb, m + half + half * 0.3, y + s(14), half * 0.4, s(96), UI.GOLD, not champ)
    UI.textCentered(bb, UI.face(13, champ), "Champion du monde", m + half + half / 2, y + s(126), champ and UI.BLACK or UI.LIGHT)
    Draw.rect(bb, m - s(4), y + s(114), W - 2 * m + s(8), s(9), { 214, 190, 150 }, 0xA0)
    y = y + s(170)
    -- palmarès
    UI.text(bb, UI.face(16, true), "Palmarès", m, y)
    y = y + UI.lineHeight(UI.face(16, true))
    local pal = app.career.palmares
    if #pal == 0 then
        UI.text(bb, UI.face(14), "Encore aucun titre. Le premier vous attend sur le circuit !", m, y, UI.DIM)
    else
        for i = #pal, math.max(1, #pal - 12), -1 do
            local e = pal[i]
            UI.text(bb, UI.face(14), "Saison " .. e.season .. " — " .. e.title .. "  (" .. os.date("%d/%m/%Y", e.time) .. ")", m, y)
            y = y + UI.lineHeight(UI.face(14))
        end
    end
end

---------------------------------------------------------------------------
-- Partie libre
---------------------------------------------------------------------------

Menus.Free = UI.Canvas:extend{ app = nil }

function Menus.Free:setup()
    self.cadence = self.app.profile.free_cadence or "rapide"
    self.color = self.app.profile.free_color or "aleatoire"
end

function Menus.Free:draw(bb)
    local app = self.app
    local W = self.W
    local m = s(20)
    local y = self:header(bb, "Partie libre", "Menu", function() self:close() end)
    y = y + s(16)
    local fg = app.data.free_game
    if fg and not fg.result then
        local bw = W - 2 * m
        bb:paintBorder(m, y, bw, s(70), s(1), UI.BLACK, s(12))
        UI.text(bb, UI.face(17, true), "Reprendre la partie en cours", m + s(16), y + s(10))
        UI.text(bb, UI.face(14), "contre " .. fg.opp.name .. " (" .. fg.opp.elo .. ") · " .. #fg.moves .. " coups joués",
            m + s(16), y + s(38), UI.DIM)
        self:region(m, y, bw, s(70), function() app:resumeFree() end)
        y = y + s(90)
    end
    local function group(title, options, current, set)
        UI.text(bb, UI.face(16, true), title, m, y)
        y = y + UI.lineHeight(UI.face(16, true)) + s(4)
        local x = m
        local f = UI.face(15)
        for _, o in ipairs(options) do
            local w = UI.textWidth(f, o[2]) + s(30)
            if x + w > W - m then x = m; y = y + s(48) end
            local sel = o[1] == current
            UI.pill(bb, x, y, w, s(38), o[2], f, sel and { dark = true } or {})
            self:region(x, y, w, s(38), function() set(o[1]); self:refresh() end)
            x = x + w + s(10)
        end
        y = y + s(60)
    end
    group("Cadence", { { "blitz", "Blitz 3 + 5" }, { "rapide", "Rapide 10 + 5" }, { "sans", "Sans pendule" } },
        self.cadence, function(v) self.cadence = v end)
    group("Couleur", { { "w", "Blancs" }, { "b", "Noirs" }, { "aleatoire", "Au hasard" } },
        self.color, function(v) self.color = v end)
    local txt = "Votre adversaire est un joueur du circuit proche de votre Elo (" .. app.profile.player_elo
        .. "), avec sa personnalité. Pas de coach, pas de retour en arrière : une vraie partie. Elle compte pour votre Elo."
    for _, l in ipairs(UI.wrap(UI.face(14), txt, W - 2 * m)) do
        UI.text(bb, UI.face(14), l, m, y, UI.DIM)
        y = y + UI.lineHeight(UI.face(14))
    end
    y = y + s(20)
    local bw = s(240)
    UI.pill(bb, (W - bw) / 2, y, bw, s(46), "Commencer", UI.face(18, true), { dark = true })
    self:region((W - bw) / 2, y, bw, s(46), function()
        app.profile.free_cadence = self.cadence
        app.profile.free_color = self.color
        local start = function() app:startFree(self.cadence, self.color) end
        if fg and not fg.result and #fg.moves >= 2 then
            UIManager:show(ConfirmBox:new{
                text = "La partie libre en cours sera comptée comme abandonnée. Continuer ?",
                ok_text = "Nouvelle partie", cancel_text = "Annuler", ok_callback = start,
            })
        else
            start()
        end
    end)
end

---------------------------------------------------------------------------
-- Profil
---------------------------------------------------------------------------

Menus.Profile = UI.Canvas:extend{ app = nil }

local MODE_NAMES = { coach = "Coach", libre = "Partie libre", tournoi = "Tournoi", candidats = "Candidats", monde = "Championnat" }

function Menus.Profile:draw(bb)
    local app = self.app
    local p = app.profile
    local W = self.W
    local m = s(16)
    local y = self:header(bb, "Profil", "Menu", function() self:close() end)
    y = y + s(12)
    UI.text(bb, UI.face(15), "Votre Elo", m, y, UI.GRAY)
    y = y + UI.lineHeight(UI.face(15))
    local ew = UI.text(bb, UI.face(40, true), tostring(p.player_elo), m, y)
    local wins, draws, losses = 0, 0, 0
    for _, h in ipairs(app.data.history) do
        if h.score == 1 then wins = wins + 1 elseif h.score == 0 then losses = losses + 1 elseif h.score then draws = draws + 1 end
    end
    UI.text(bb, UI.face(15), plural(p.games_played, "partie classée", "parties classées"), m + ew + s(20), y + s(8), UI.DIM)
    UI.text(bb, UI.face(15), plural(wins, "victoire") .. " · " .. plural(draws, "nulle") .. " · " .. plural(losses, "défaite"),
        m + ew + s(20), y + s(32), UI.DIM)
    y = y + UI.lineHeight(UI.face(40, true)) + s(6)
    local bw = s(170)
    UI.pill(bb, W - m - bw, s(52), bw, s(34), "Régler mon Elo", UI.face(14))
    self:region(W - m - bw, s(52), bw, s(34), function()
        UIManager:show(SpinWidget:new{
            title_text = "Mon Elo", value = p.player_elo, value_min = 100, value_max = 3000,
            value_step = 10, value_hold_step = 100, ok_text = "Valider", cancel_text = "Annuler",
            callback = function(spin) p.player_elo = spin.value; app:save(); self:refresh() end,
        })
    end)

    -- courbe d'Elo
    local hist = {}
    for _, h in ipairs(app.data.history) do
        if h.elo_after then
            if #hist == 0 and h.elo_before then hist[1] = h.elo_before end
            hist[#hist + 1] = h.elo_after
        end
    end
    local gh = s(150)
    local gw = W - 2 * m
    bb:paintBorder(m, y, gw, gh, 1, UI.LIGHT)
    if #hist >= 2 then
        local lo, hi = math.huge, -math.huge
        for _, v in ipairs(hist) do lo = math.min(lo, v); hi = math.max(hi, v) end
        if hi - lo < 40 then lo = lo - 20; hi = hi + 20 end
        local n = #hist
        local function pt(i) return m + s(10) + (gw - s(20)) * (i - 1) / (n - 1), y + gh - s(14) - (gh - s(28)) * (hist[i] - lo) / (hi - lo) end
        for i = 1, n - 1 do
            local x0, y0 = pt(i)
            local x1, y1 = pt(i + 1)
            Draw.line(bb, x0, y0, x1, y1, s(3), nil, 0x22)
        end
        UI.text(bb, UI.face(12), tostring(math.floor(hi)), m + s(6), y + s(4), UI.GRAY)
        UI.text(bb, UI.face(12), tostring(math.floor(lo)), m + s(6), y + gh - s(22), UI.GRAY)
    else
        UI.textCentered(bb, UI.face(14), "Votre courbe d'Elo apparaîtra après quelques parties.", W / 2, y + gh / 2 - s(10), UI.GRAY)
    end
    y = y + gh + s(16)

    UI.text(bb, UI.face(16, true), "Dernières parties", m, y)
    y = y + UI.lineHeight(UI.face(16, true)) + s(4)
    local f = UI.face(14)
    local lh = UI.lineHeight(f)
    local h = app.data.history
    for i = #h, 1, -1 do
        if y > self.H - lh * 2 - s(10) then break end
        local e = h[i]
        local res = e.score == 1 and "Victoire" or (e.score == 0 and "Défaite" or "Nulle")
        local opp = e.opp or ("IA " .. (e.ai_elo or "?"))
        local line1 = (e.date or "") .. " · " .. (MODE_NAMES[e.mode or "coach"] or "") .. " · " .. res .. " contre " .. opp
        UI.text(bb, f, UI.ellipsize(f, line1, W - 2 * m), m, y)
        y = y + lh
        local d = (e.elo_after and e.elo_before) and (e.elo_after - e.elo_before) or nil
        local line2 = (e.label and (e.label .. " · ") or "") .. (e.reason or "")
            .. (e.accuracy and (" · précision " .. e.accuracy .. " %") or "")
            .. (d and string.format(" · Elo %s%d", d >= 0 and "+" or "", d) or " · non classée")
        UI.text(bb, UI.face(13), UI.ellipsize(UI.face(13), line2, W - 2 * m), m, y, UI.GRAY)
        y = y + lh + s(4)
    end
end

---------------------------------------------------------------------------
-- Parties jouées (à analyser avec le coach)
---------------------------------------------------------------------------

Menus.Archive = UI.Canvas:extend{ app = nil }

function Menus.Archive:setup() self.page = 1 end

local ARCH_MODES = { coach = "Coach", libre = "Partie libre", tournoi = "Tournoi", candidats = "Candidats", monde = "Championnat" }

function Menus.Archive:draw(bb)
    local app = self.app
    local W = self.W
    local m = s(16)
    local y = self:header(bb, "Analyser une partie", "Retour", function() self:close() end)
    y = y + s(8)
    local list = app.data.archive or {}
    if #list == 0 then
        for _, l in ipairs(UI.wrap(UI.face(15), "Aucune partie terminée pour l'instant. Vos parties de tournoi, de partie libre et du coach apparaîtront ici.", W - 2 * m)) do
            UI.text(bb, UI.face(15), l, m, y, UI.DIM)
            y = y + UI.lineHeight(UI.face(15))
        end
        return
    end
    local rowh = s(56)
    local per = math.max(1, math.floor((self.H - y - s(60)) / rowh))
    local pages = math.max(1, math.ceil(#list / per))
    if self.page > pages then self.page = pages end
    self.pages = pages
    local first = #list - (self.page - 1) * per
    for i = first, math.max(1, first - per + 1), -1 do
        local e = list[i]
        local f, fb = UI.face(15), UI.face(16, true)
        local score = (e.result == "1/2-1/2") and "½-½" or (e.result or "*")
        UI.text(bb, fb, UI.ellipsize(fb, e.white .. " – " .. e.black, W - 2 * m - s(80)), m, y + s(4))
        UI.textRight(bb, fb, score, W - m, y + s(4))
        local sub = os.date("%d/%m/%Y", e.time) .. " · " .. (ARCH_MODES[e.mode] or "") .. (e.label and (" · " .. e.label) or "")
            .. " · " .. math.ceil(#e.moves / 2) .. " coups"
        UI.text(bb, UI.face(13), UI.ellipsize(UI.face(13), sub, W - 2 * m), m, y + s(30), UI.GRAY)
        bb:paintRect(m, y + rowh - 1, W - 2 * m, 1, UI.LIGHT)
        self:region(0, y, W, rowh, function()
            self:close("none")
            app:analyseArchived(e)
        end)
        y = y + rowh
    end
    if pages > 1 then
        local f = UI.face(16)
        local yb = self.H - s(46)
        UI.textCentered(bb, f, "‹    page " .. self.page .. " / " .. pages .. "    ›", W / 2, yb, UI.DIM)
        self:region(0, yb - s(10), W / 2, s(50), function() self:onPrevKey() end)
        self:region(W / 2, yb - s(10), W / 2, s(50), function() self:onNextKey() end)
    end
end

function Menus.Archive:onPrevKey()
    if self.page > 1 then self.page = self.page - 1; self:refresh() end
end

function Menus.Archive:onNextKey()
    if self.page < (self.pages or 1) then self.page = self.page + 1; self:refresh() end
end

function Menus.Archive:onSwipe(dir)
    if dir == "west" then self:onNextKey() elseif dir == "east" then self:onPrevKey() end
end

---------------------------------------------------------------------------
-- Bilan d'une partie
---------------------------------------------------------------------------

Menus.Bilan = UI.Canvas:extend{ app = nil, match = nil, actions = nil }

function Menus.Bilan:setup()
    -- compléter les évaluations manquantes pour la courbe
    self.analysing = true
    self.match.onUpdate = function(ev)
        if ev == "analysis" and not self.closed then self:refresh("ui") end
    end
    self.match:analyseAll(function()
        self.analysing = false
        if not self.closed then self:refresh("ui") end
    end)
end

function Menus.Bilan:draw(bb)
    local m = self.match
    local g = m.g
    local W = self.W
    local mg = s(18)
    local y = s(22)
    local title = g.score == 1 and "Victoire" or (g.score == 0 and "Défaite" or "Nulle")
    UI.textCentered(bb, UI.face(32, true), title, W / 2, y)
    y = y + UI.lineHeight(UI.face(32, true))
    UI.textCentered(bb, UI.face(15), (g.reason or ""), W / 2, y, UI.DIM)
    y = y + UI.lineHeight(UI.face(15)) + s(4)
    local vs = "contre " .. g.opp.name .. ((g.opp.name):find("^IA ") and "" or (" (" .. g.opp.elo .. ")")) .. (g.label and ("  ·  " .. g.label) or "")
    UI.textCentered(bb, UI.face(15), UI.ellipsize(UI.face(15), vs, W - 2 * mg), W / 2, y)
    y = y + UI.lineHeight(UI.face(15)) + s(12)

    -- Elo
    if g.elo_before and g.elo_after then
        local d = g.elo_after - g.elo_before
        local txt = string.format("Elo  %d → %d  (%s%d)", g.elo_before, g.elo_after, d >= 0 and "+" or "", d)
        local f = UI.face(18, true)
        local w = UI.textWidth(f, txt) + s(40)
        Draw.roundedRect(bb, (W - w) / 2, y, w, s(40), s(20), d > 0 and UI.GREEN or (d < 0 and UI.RED or nil), d >= 0 and 0xD8 or 0xB0)
        UI.textCentered(bb, f, txt, W / 2, y + (s(40) - UI.lineHeight(f)) / 2 + s(2))
        y = y + s(54)
    elseif g.takeback then
        UI.textCentered(bb, UI.face(14), "Partie non classée (des coups ont été repris).", W / 2, y, UI.GRAY)
        y = y + s(30)
    end

    -- précision et catégories (coach)
    local marks = {}
    if m:isCoach() then
        local acc = m:accuracy()
        if acc then
            UI.textCentered(bb, UI.face(17, true), string.format("Précision : %d %%", math.floor(acc + 0.5)), W / 2, y)
            y = y + UI.lineHeight(UI.face(17, true)) + s(6)
        end
        local counts = m:categoryCounts()
        local chips = {}
        for _, id in ipairs(Coach.ORDER) do
            if counts[id] then chips[#chips + 1] = { id = id, txt = Coach.CATEGORIES[id].symbol .. " " .. Coach.CATEGORIES[id].label .. " " .. counts[id] } end
        end
        local f = UI.face(13)
        local x = mg
        for _, c in ipairs(chips) do
            local w = UI.textWidth(f, c.txt) + s(20)
            if x + w > W - mg then x = mg; y = y + s(34) end
            local cat = Coach.CATEGORIES[c.id]
            Draw.roundedRect(bb, x, y, w, s(28), s(14), cat.color, cat.gray)
            UI.textCentered(bb, f, c.txt, x + w / 2, y + (s(28) - UI.lineHeight(f)) / 2 + s(1))
            x = x + w + s(8)
        end
        if #chips > 0 then y = y + s(42) end
        for ply, a in pairs(g.annotations) do
            local cat = Coach.CATEGORIES[a.cls]
            if cat and cat.rank >= 7 or a.cls == "brillant" then
                marks[#marks + 1] = { idx = ply, color = cat.color, gray = cat.gray }
            end
        end
    end

    -- graphique
    UI.text(bb, UI.face(14), "Avantage au fil de la partie" .. (self.analysing and " (analyse en cours…)" or ""), mg, y, UI.GRAY)
    UI.textRight(bb, UI.face(12), "blancs ↑   noirs ↓", W - mg, y + s(2), UI.GRAY)
    y = y + UI.lineHeight(UI.face(14)) + s(2)
    local raw, n = m:evalSeries()
    -- léger lissage : les analyses rapides oscillent d'un demi-coup à l'autre
    local vals = {}
    for i = 0, n do
        local a, b, c = raw[math.max(0, i - 1)], raw[i], raw[math.min(n, i + 1)]
        if math.abs(b) >= 9000 then vals[i] = b else vals[i] = (a + 2 * b + c) / 4 end
    end
    local gh = s(170)
    local gx, gw = mg, W - 2 * mg
    local toIdx = Menus.drawEvalGraph(bb, gx, y, gw, gh, vals, n, marks)
    self:region(gx, y, gw, gh, function(ges)
        local idx = toIdx(ges.pos.x)
        if idx and self.actions.review then self.actions.review(idx) end
    end)
    y = y + gh + s(6)
    UI.textCentered(bb, UI.face(12), "Touchez le graphique pour revoir ce moment de la partie.", W / 2, y, UI.GRAY)
    y = y + s(40)

    -- boutons
    local buttons = {}
    buttons[#buttons + 1] = { "Revoir la partie", function() self.actions.review(nil) end }
    if self.actions.analyse then buttons[#buttons + 1] = { "Analyser avec le coach", self.actions.analyse } end
    if self.actions.continue then buttons[#buttons + 1] = { self.actions.continue_label or "Continuer", self.actions.continue, true } end
    if self.actions.newGame then buttons[#buttons + 1] = { "Nouvelle partie", self.actions.newGame, true } end
    buttons[#buttons + 1] = { "Menu principal", self.actions.menu }
    local bh = s(44)
    local bw = math.floor(W * 0.6)
    for _, b in ipairs(buttons) do
        UI.pill(bb, (W - bw) / 2, y, bw, bh, b[1], UI.face(16, b[3]), b[3] and { dark = true } or {})
        self:region((W - bw) / 2, y, bw, bh, b[2])
        y = y + bh + s(12)
    end
end

function Menus.Bilan:onClose()
    self.match.onUpdate = function() end
    if self.actions.closed then self.actions.closed() end
end

return Menus
