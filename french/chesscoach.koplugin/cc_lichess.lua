--[[
  Jeu en ligne sur Lichess, avec l'échiquier et la pendule de l'application.

  Utilise l'entrée officielle de Lichess pour les échiquiers externes (« Board API ») :
  - le joueur autorise l'application une fois avec une clé créée sur son compte Lichess
    (permission « Jouer avec l'API échiquier ») ; le mot de passe n'est jamais demandé ;
  - cadences permises par Lichess : rapide et classique (pas de blitz ni de bullet) ;
  - aucune aide de moteur pendant ces parties (règle de Lichess) : le coach est coupé.

  Technique : les « flux » Lichess sont des connexions qui restent ouvertes et envoient une
  ligne de texte à chaque évènement. On les lit sans bloquer l'écran, quelques fois par seconde.
  La logique (Stream, Session, Online) est séparée des écrans pour être testée sur ordinateur.
]]

local Chess = require("cc_chess")

local Lichess = {}

Lichess.HOST = "lichess.org"
Lichess.PORT = 443
Lichess.VERIFY = true        -- vérifier le certificat du site
Lichess.CAFILE = nil         -- rempli par l'application (certificats de KOReader)
Lichess.TIMEOUT = 10
Lichess.DEAD_AFTER = 25      -- Lichess envoie un signe de vie toutes les quelques secondes : au-delà, connexion morte

-- Cadences proposées (toutes acceptées par l'entrée « échiquier » de Lichess)
Lichess.CADENCES = {
    { id = "10+0", name = "10 + 0", time = 10, inc = 0 },
    { id = "10+5", name = "10 + 5", time = 10, inc = 5 },
    { id = "15+10", name = "15 + 10", time = 15, inc = 10 },
    { id = "30+0", name = "30 + 0", time = 30, inc = 0 },
    { id = "30+20", name = "30 + 20", time = 30, inc = 20 },
}

function Lichess.cadence(id)
    for _, c in ipairs(Lichess.CADENCES) do if c.id == id then return c end end
    return Lichess.CADENCES[2]
end

local function decode(line)
    local ok, JSON = pcall(require, "json")
    if not ok then ok, JSON = pcall(require, "dkjson") end
    if not ok then return nil end
    local ok2, v = pcall(JSON.decode, line)
    if not ok2 then return nil end
    -- les valeurs « null » du JSON deviennent de vraies valeurs absentes
    local function clean(t, depth)
        if type(t) ~= "table" or depth > 8 then return end
        for k, x in pairs(t) do
            local ty = type(x)
            if ty == "table" then clean(x, depth + 1)
            elseif ty ~= "string" and ty ~= "number" and ty ~= "boolean" then t[k] = nil end
        end
    end
    clean(v, 0)
    return v
end
Lichess.decode = decode

local function sslParams()
    local p = { mode = "client", protocol = "any", options = { "all", "no_sslv2", "no_sslv3" }, verify = "none" }
    if Lichess.VERIFY and Lichess.CAFILE then
        p.verify = "peer"
        p.cafile = Lichess.CAFILE
    end
    return p
end

---------------------------------------------------------------------------
-- Requête simple (bloque au plus quelques secondes)
---------------------------------------------------------------------------

-- Renvoie : code HTTP (ou nil), texte de la réponse ou message d'erreur
function Lichess.request(method, path, token, body)
    local socket = require("socket")
    local ssl = require("ssl")
    local sock = socket.tcp()
    sock:settimeout(Lichess.TIMEOUT)
    local ok, err = sock:connect(Lichess.HOST, Lichess.PORT)
    if not ok then sock:close() return nil, "connexion impossible (" .. tostring(err) .. ")" end
    local s
    s, err = ssl.wrap(sock, sslParams())
    if not s then sock:close() return nil, "connexion sécurisée impossible (" .. tostring(err) .. ")" end
    pcall(s.sni, s, Lichess.HOST)
    ok, err = s:dohandshake()
    if not ok then s:close() return nil, "connexion sécurisée refusée (" .. tostring(err) .. ")" end
    s:settimeout(Lichess.TIMEOUT)
    local req = { method .. " " .. path .. " HTTP/1.1", "Host: " .. Lichess.HOST, "Accept: application/json",
        "User-Agent: LeCircuit-KOReader", "Connection: close" }
    if token then req[#req + 1] = "Authorization: Bearer " .. token end
    if body then
        req[#req + 1] = "Content-Type: application/x-www-form-urlencoded"
        req[#req + 1] = "Content-Length: " .. #body
    elseif method == "POST" then
        req[#req + 1] = "Content-Length: 0"
    end
    s:send(table.concat(req, "\r\n") .. "\r\n\r\n" .. (body or ""))
    local data, _, partial = s:receive("*a")
    s:close()
    data = data or partial or ""
    local code = tonumber(data:match("^HTTP/%d%.%d (%d+)"))
    if not code then return nil, "pas de réponse du serveur" end
    local head, rest = data:match("^(.-)\r\n\r\n(.*)$")
    rest = rest or ""
    if head and head:lower():find("transfer%-encoding: chunked") then
        local out, pos = {}, 1
        while true do
            local a, b, hex = rest:find("^(%x+)[^\r\n]*\r\n", pos)
            if not a then break end
            local n = tonumber(hex, 16)
            if n == 0 then break end
            out[#out + 1] = rest:sub(b + 1, b + n)
            pos = b + n + 3
        end
        rest = table.concat(out)
    end
    return code, rest
end

---------------------------------------------------------------------------
-- Connexion gardée ouverte pour envoyer les coups
-- (ouvrir une connexion sécurisée coûte plusieurs allers-retours et un gros calcul
--  sur la liseuse : on la prépare au début de la partie et on la réutilise)
---------------------------------------------------------------------------

local Keep = {}
Keep.__index = Keep
Lichess.Keep = Keep

function Keep.new(token) return setmetatable({ token = token, sock = nil, opened = 0 }, Keep) end

function Keep:open()
    if self.sock then return true end
    local socket = require("socket")
    local ssl = require("ssl")
    local sock = socket.tcp()
    sock:settimeout(Lichess.TIMEOUT)
    pcall(sock.setoption, sock, "tcp-nodelay", true)
    local ok, err = sock:connect(Lichess.HOST, Lichess.PORT)
    if not ok then sock:close() return nil, tostring(err) end
    local s
    s, err = ssl.wrap(sock, sslParams())
    if not s then sock:close() return nil, tostring(err) end
    pcall(s.sni, s, Lichess.HOST)
    ok, err = s:dohandshake()
    if not ok then s:close() return nil, tostring(err) end
    s:settimeout(Lichess.TIMEOUT)
    self.sock = s
    self.opened = self.opened + 1
    return true
end

function Keep:close()
    if self.sock then pcall(self.sock.close, self.sock) end
    self.sock = nil
end

-- Une requête sur la connexion gardée ; une seule nouvelle tentative si elle a été coupée
function Keep:post(path)
    for attempt = 1, 2 do
        local ok, err = self:open()
        if not ok then return nil, "connexion impossible (" .. err .. ")" end
        local s = self.sock
        local req = "POST " .. path .. " HTTP/1.1\r\nHost: " .. Lichess.HOST
            .. "\r\nUser-Agent: LeCircuit-KOReader\r\nAccept: application/json\r\nConnection: keep-alive"
            .. "\r\nAuthorization: Bearer " .. self.token .. "\r\nContent-Length: 0\r\n\r\n"
        local sent = s:send(req)
        local status = sent and s:receive("*l")
        local code = status and tonumber(status:match("^HTTP/%d%.%d (%d+)"))
        if code then
            local len, chunked, close = 0, false, false
            while true do
                local h = s:receive("*l")
                if not h or h == "" then break end
                local k, v = h:match("^([^:]+):%s*(.*)$")
                if k then
                    k = k:lower()
                    if k == "content-length" then len = tonumber(v) or 0
                    elseif k == "transfer-encoding" and v:lower():find("chunked") then chunked = true
                    elseif k == "connection" and v:lower():find("close") then close = true end
                end
            end
            local body = ""
            if chunked then
                local parts = {}
                while true do
                    local sz = s:receive("*l")
                    local n = sz and tonumber(sz:match("^(%x+)"), 16)
                    if not n or n == 0 then s:receive("*l") break end
                    parts[#parts + 1] = s:receive(n) or ""
                    s:receive("*l")
                end
                body = table.concat(parts)
            elseif len > 0 then
                body = s:receive(len) or ""
            end
            if close then self:close() end
            return code, body
        end
        -- connexion fermée par le serveur entre-temps : on en rouvre une
        self:close()
    end
    return nil, "pas de réponse du serveur"
end

---------------------------------------------------------------------------
-- Flux : connexion qui reste ouverte, lue sans bloquer
---------------------------------------------------------------------------

local Stream = {}
Stream.__index = Stream
Lichess.Stream = Stream

function Stream.open(method, path, token, body)
    local socket = require("socket")
    local ssl = require("ssl")
    local sock = socket.tcp()
    sock:settimeout(Lichess.TIMEOUT)
    local ok, err = sock:connect(Lichess.HOST, Lichess.PORT)
    if not ok then sock:close() return nil, tostring(err) end
    local s
    s, err = ssl.wrap(sock, sslParams())
    if not s then sock:close() return nil, tostring(err) end
    pcall(s.sni, s, Lichess.HOST)
    ok, err = s:dohandshake()
    if not ok then s:close() return nil, tostring(err) end
    local req = { method .. " " .. path .. " HTTP/1.1", "Host: " .. Lichess.HOST, "Accept: application/x-ndjson",
        "User-Agent: LeCircuit-KOReader", "Authorization: Bearer " .. token }
    if body then
        req[#req + 1] = "Content-Type: application/x-www-form-urlencoded"
        req[#req + 1] = "Content-Length: " .. #body
    end
    s:settimeout(Lichess.TIMEOUT)
    s:send(table.concat(req, "\r\n") .. "\r\n\r\n" .. (body or ""))
    s:settimeout(0)
    return setmetatable({ sock = s, raw = "", body = "", headers = nil, chunked = false, closed = false,
        code = nil, opened = os.time(), last = os.time() }, Stream)
end

function Stream:close()
    if self.sock then pcall(self.sock.close, self.sock) end
    self.sock = nil
    self.closed = true
end

-- Lit ce qui est arrivé. Renvoie la liste des lignes complètes (texte), éventuellement vide.
function Stream:poll()
    local lines = {}
    if not self.sock then return lines end
    for _ = 1, 64 do
        local d, err, part = self.sock:receive(8192)
        local chunk = d or part
        if chunk and #chunk > 0 then
            self.raw = self.raw .. chunk
            self.last = os.time()
        end
        if err and err ~= "timeout" and err ~= "wantread" and err ~= "wantwrite" then
            self.closed = true
            pcall(self.sock.close, self.sock)
            self.sock = nil
            break
        end
        if not d then break end
    end
    if not self.headers then
        local a, b = self.raw:find("\r\n\r\n", 1, true)
        if not a then return lines end
        self.headers = self.raw:sub(1, a - 1)
        self.raw = self.raw:sub(b + 1)
        self.code = tonumber(self.headers:match("^HTTP/%d%.%d (%d+)"))
        self.chunked = self.headers:lower():find("transfer%-encoding: chunked") ~= nil
    end
    if self.chunked then
        while true do
            local a, b, hex = self.raw:find("^(%x+)[^\r\n]*\r\n")
            if not a then break end
            local n = tonumber(hex, 16)
            if n == 0 then
                self.ended = true
                break
            end
            if #self.raw < b + n + 2 then break end
            self.body = self.body .. self.raw:sub(b + 1, b + n)
            self.raw = self.raw:sub(b + n + 3)
        end
    else
        self.body = self.body .. self.raw
        self.raw = ""
    end
    while true do
        local a = self.body:find("\n", 1, true)
        if not a then break end
        local line = self.body:sub(1, a - 1):gsub("\r$", "")
        self.body = self.body:sub(a + 1)
        if line ~= "" then lines[#lines + 1] = line end
    end
    if self.ended then self:close() end
    return lines
end

---------------------------------------------------------------------------
-- Une partie en ligne (état reconstruit à partir des messages de Lichess)
---------------------------------------------------------------------------

local Online = {}
Online.__index = Online
Lichess.Online = Online

local STATUS_FR = {
    mate = "échec et mat", resign = "abandon", stalemate = "pat", timeout = "adversaire parti",
    draw = "nulle", outoftime = "temps écoulé", aborted = "partie annulée", noStart = "partie non commencée",
    cheat = "triche détectée", variantEnd = "fin de partie",
}

function Online.new(id, myName, now)
    return setmetatable({ id = id, me_name = myName and myName:lower() or nil, now = now or os.time,
        moves = {}, positions = { Chess.new() }, status = "created", clock = { w = 0, b = 0 }, stamp = 0,
        players = { w = {}, b = {} }, me = nil, loaded = false }, Online)
end

local function player(p)
    p = p or {}
    local name = p.name or p.id
    if not name and p.aiLevel then name = "Stockfish niveau " .. p.aiLevel end
    return { name = name or "Anonyme", rating = p.rating, title = p.title, id = p.id }
end

local CASTLE_FIX = { e1h1 = "e1g1", e1a1 = "e1c1", e8h8 = "e8g8", e8a8 = "e8c8" }

function Online:_setMoves(str)
    local list = {}
    for u in (str or ""):gmatch("%S+") do list[#list + 1] = u end
    -- on ne rejoue que ce qui a changé
    local keep = 0
    for i = 1, math.min(#list, #self.moves) do
        if list[i] ~= self.moves[i] then break end
        keep = i
    end
    for i = #self.moves, keep + 1, -1 do
        self.moves[i] = nil
        self.positions[i + 1] = nil
    end
    for i = keep + 1, #list do
        local pos = self.positions[i]
        local m = pos:findUci(list[i])
        if not m and CASTLE_FIX[list[i]] then m = pos:findUci(CASTLE_FIX[list[i]]) end
        if not m then break end
        self.moves[i] = list[i]
        self.positions[i + 1] = pos:makeMove(m)
        self.last = { from = m.from, to = m.to }
    end
    if #self.moves == 0 then self.last = nil end
end

function Online:_state(st)
    if not st then return end
    self:_setMoves(st.moves)
    self.clock.w = (tonumber(st.wtime) or 0) / 1000
    self.clock.b = (tonumber(st.btime) or 0) / 1000
    self.stamp = self.now()
    self.status = st.status or self.status
    self.winner = st.winner
    self.draw_offer = { w = st.wdraw and true or false, b = st.bdraw and true or false }
    self.pending = nil
end

-- Applique un message du flux de la partie. Renvoie le type du message.
function Online:apply(ev)
    if type(ev) ~= "table" then return nil end
    if ev.type == "gameFull" then
        self.players.w = player(ev.white)
        self.players.b = player(ev.black)
        self.rated = ev.rated
        self.speed = ev.speed
        if ev.clock then
            self.base = (tonumber(ev.clock.initial) or 0) / 1000
            self.inc = (tonumber(ev.clock.increment) or 0) / 1000
        end
        if self.me_name then
            if (self.players.w.id or ""):lower() == self.me_name or (self.players.w.name or ""):lower() == self.me_name then
                self.me = "w"
            else
                self.me = "b"
            end
        end
        if ev.initialFen and ev.initialFen ~= "startpos" then
            self.positions = { Chess.new(ev.initialFen) }
            self.moves = {}
        end
        self.loaded = true
        self:_state(ev.state)
    elseif ev.type == "gameState" then
        self:_state(ev)
    elseif ev.type == "opponentGone" then
        self.gone = ev.gone and true or false
        self.claim_in = ev.claimWinInSeconds
        self.gone_stamp = self.now()
    end
    return ev.type
end

function Online:pos()
    if self.pending then return self.pending.pos end
    return self.positions[#self.positions]
end
function Online:turn() return self:pos().turn end
function Online:ended() return self.status ~= "created" and self.status ~= "started" end
function Online:myTurn() return self.loaded and not self:ended() and not self.pending and self:turn() == self.me end

-- La pendule tourne après le premier coup de chaque camp
function Online:clockRunning() return self.status == "started" and #self.moves >= 2 end

function Online:time(color)
    local t = self.clock[color] or 0
    if self:clockRunning() and self.positions[#self.positions].turn == color then
        t = t - (self.now() - self.stamp)
    end
    return math.max(0, t)
end

-- Affiche tout de suite le coup du joueur, en attendant la confirmation de Lichess
function Online:setPending(m)
    local pos = self.positions[#self.positions]
    self.pending = { pos = pos:makeMove(m), uci = Chess.moveToUci(m), last = { from = m.from, to = m.to } }
end
function Online:clearPending() self.pending = nil end
function Online:lastMove()
    if self.pending then return self.pending.last end
    return self.last
end

-- « Victoire · abandon »
function Online:resultText()
    if not self:ended() then return nil end
    local why = STATUS_FR[self.status] or self.status
    if self.status == "aborted" or self.status == "noStart" then return "Partie annulée" end
    if not self.winner then return "Partie nulle · " .. why end
    local won = (self.winner == "white") == (self.me == "w")
    return (won and "Victoire" or "Défaite") .. " · " .. why
end

---------------------------------------------------------------------------
-- Session : la clé, les flux ouverts, la recherche d'adversaire
---------------------------------------------------------------------------

local Session = {}
Session.__index = Session
Lichess.Session = Session

function Session.new(token, now)
    return setmetatable({ token = token, now = now or os.time, state = "repos" }, Session)
end

-- Vérifie la clé et lit le compte. Renvoie true ou nil, message
function Session:login()
    local code, body = Lichess.request("GET", "/api/account", self.token)
    if not code then return nil, body end
    if code == 401 then return nil, "Lichess refuse cette clé. Vérifiez qu'elle est complète." end
    if code ~= 200 then return nil, "Lichess a répondu une erreur (" .. code .. ")." end
    local acc = decode(body)
    if not acc or not acc.username then return nil, "Réponse de Lichess illisible." end
    self.username = acc.username
    self.perfs = {}
    for _, k in ipairs({ "rapid", "classical", "blitz" }) do
        local p = acc.perfs and acc.perfs[k]
        if p then self.perfs[k] = { rating = p.rating, games = p.games, prov = p.prov } end
    end
    return true
end

function Session:_openEvents()
    if self.events and not self.events.closed then return true end
    local st, err = Stream.open("GET", "/api/stream/event", self.token)
    if not st then return nil, err end
    self.events = st
    return true
end

-- Lance la recherche d'un adversaire
function Session:seek(cadence, rated)
    local ok, err = self:_openEvents()
    if not ok then return nil, "Connexion à Lichess impossible (" .. tostring(err) .. ")." end
    local body = "rated=" .. (rated and "true" or "false") .. "&time=" .. cadence.time .. "&increment=" .. cadence.inc
        .. "&variant=standard&color=random"
    local st
    st, err = Stream.open("POST", "/api/board/seek", self.token, body)
    if not st then return nil, "Connexion à Lichess impossible (" .. tostring(err) .. ")." end
    self.seeking = st
    self.seek_since = self.now()
    self.state = "recherche"
    return true
end

function Session:cancelSeek()
    if self.seeking then self.seeking:close() end
    self.seeking = nil
    if self.state == "recherche" then self.state = "repos" end
end

-- Surveille les parties en cours (pour reprendre une partie déjà commencée)
function Session:watch()
    return self:_openEvents()
end

function Session:openGame(id)
    self:cancelSeek()
    local st, err = Stream.open("GET", "/api/board/game/stream/" .. id, self.token)
    if not st then return nil, err end
    self.game_stream = st
    self.game = self.game or Online.new(id, self.username, self.now)
    self.game.id = id
    self.state = "partie"
    -- connexion pour les coups préparée tout de suite (pendant que l'écran s'ouvre)
    self.keep = self.keep or Keep.new(self.token)
    self.keep:open()
    return self.game
end

function Session:closeGame()
    if self.keep then self.keep:close() end
    if self.game_stream then self.game_stream:close() end
    self.game_stream, self.game = nil, nil
    if self.state == "partie" then self.state = "repos" end
end

function Session:closeAll()
    self:cancelSeek()
    self:closeGame()
    if self.events then self.events:close() end
    self.events = nil
    self.state = "repos"
end

--[[
  À appeler quelques fois par seconde. Renvoie une liste d'évènements pour l'écran :
  { kind = "gameStart", id = … } / { kind = "game", type = … } / { kind = "seekError", text = … }
  / { kind = "reconnect" }
]]
function Session:pump()
    local out = {}
    if self.events then
        for _, line in ipairs(self.events:poll()) do
            local ev = decode(line)
            if ev and ev.type == "gameStart" and ev.game then
                local id = ev.game.gameId or ev.game.id
                local compat = ev.game.compat
                if id and (not compat or compat.board ~= false) and (ev.game.variant == nil or ev.game.variant.key == "standard") then
                    out[#out + 1] = { kind = "gameStart", id = id }
                end
            end
        end
        if self.events.closed then
            self.events = nil
            if self.state == "recherche" then self:_openEvents() end
        end
    end
    if self.seeking then
        local lines = self.seeking:poll()
        if self.seeking.code and self.seeking.code >= 400 then
            local msg = decode(self.seeking.body ~= "" and self.seeking.body or (lines[1] or "")) or {}
            out[#out + 1] = { kind = "seekError", text = msg.error or ("Lichess refuse la recherche (" .. self.seeking.code .. ").") }
            self:cancelSeek()
        elseif self.seeking.closed then
            -- la recherche se termine quand un adversaire est trouvé (ou au bout d'un moment)
            self.seeking = nil
            self.seek_done = self.now()
        end
    end
    if self.state == "recherche" and not self.seeking and self.seek_done and self.now() - self.seek_done > 6 then
        out[#out + 1] = { kind = "seekError", text = "Aucun adversaire trouvé pour l'instant. Réessayez." }
        self.state = "repos"
        self.seek_done = nil
    end
    -- connexion muette trop longtemps (Wi-Fi coupé…) : on la considère perdue
    for _, k in ipairs({ "events", "game_stream" }) do
        local st = self[k]
        if st and not st.closed and os.time() - st.last > Lichess.DEAD_AFTER then st:close() end
    end
    if self.events and self.events.closed then
        self.events = nil
        if self.state == "recherche" then self:_openEvents() end
    end
    if self.game_stream and self.game then
        for _, line in ipairs(self.game_stream:poll()) do
            local ev = decode(line)
            local t = self.game:apply(ev)
            if t then out[#out + 1] = { kind = "game", type = t } end
        end
        if self.game_stream.closed then
            local code = self.game_stream.code
            self.game_stream = nil
            if code and code >= 400 then
                out[#out + 1] = { kind = "gameError", text = "Lichess refuse cette partie pour l'échiquier externe (cadence trop rapide ?)." }
            elseif not self.game:ended() then
                -- connexion coupée : on se rebranche (Lichess renvoie alors toute la partie)
                self.retry_at = self.now() + 2
                out[#out + 1] = { kind = "reconnect" }
            end
        end
    elseif self.game and not self.game:ended() and self.retry_at and self.now() >= self.retry_at then
        self.retry_at = self.now() + 5
        local st = Stream.open("GET", "/api/board/game/stream/" .. self.game.id, self.token)
        if st then
            self.game_stream = st
            self.retry_at = nil
        end
    end
    return out
end

function Session:active()
    return self.events ~= nil or self.seeking ~= nil or self.game_stream ~= nil or self.retry_at ~= nil
end

local function post(self, path)
    self.keep = self.keep or Keep.new(self.token)
    local code, body = self.keep:post(path)
    if not code then return nil, body end
    if code ~= 200 then
        local msg = decode(body or "") or {}
        return nil, msg.error or ("erreur " .. code)
    end
    return true
end

function Session:move(uci) return post(self, "/api/board/game/" .. self.game.id .. "/move/" .. uci) end
function Session:resign() return post(self, "/api/board/game/" .. self.game.id .. "/resign") end
function Session:abort() return post(self, "/api/board/game/" .. self.game.id .. "/abort") end
function Session:draw(yes) return post(self, "/api/board/game/" .. self.game.id .. "/draw/" .. (yes and "yes" or "no")) end
function Session:claimVictory() return post(self, "/api/board/game/" .. self.game.id .. "/claim-victory") end

---------------------------------------------------------------------------
-- Écrans
---------------------------------------------------------------------------

function Lichess.screens()
    local UIManager = require("ui/uimanager")
    local ConfirmBox = require("ui/widget/confirmbox")
    local InfoMessage = require("ui/widget/infomessage")
    local InputDialog = require("ui/widget/inputdialog")
    local ButtonDialog = require("ui/widget/buttondialog")
    local Geom = require("ui/geometry")
    local Board = require("cc_board")
    local Draw = require("cc_draw")
    local UI = require("cc_ui")
    local s = UI.s
    local Screens = {}

    local function info(text) UIManager:show(InfoMessage:new{ text = text }) end

    local function fmtClock(t)
        t = math.max(0, t)
        if t < 10 then return (string.format("0:%04.1f", math.floor(t * 10) / 10):gsub("%.", ",")) end
        local secs = math.ceil(t - 0.001)
        if secs >= 3600 then return string.format("%d:%02d:%02d", math.floor(secs / 3600), math.floor(secs / 60) % 60, secs % 60) end
        return string.format("%d:%02d", math.floor(secs / 60), secs % 60)
    end

    -------------------------------------------------------------------
    -- Accueil « En ligne »
    -------------------------------------------------------------------
    local Hub = UI.Canvas:extend{ app = nil }
    Screens.Hub = Hub

    function Hub:setup()
        local p = self.app.profile
        self.cadence = p.lichess_cadence or "10+5"
        self.rated = p.lichess_rated ~= false
        self.status = nil
        if self.app:lichessToken() then self:connect() end
    end

    function Hub:connect()
        local app = self.app
        self.status = "Connexion à Lichess…"
        self:refresh("ui")
        app:whenOnline(function()
            if self.closed then return end
            local ses = Session.new(app:lichessToken(), app._clock)
            local ok, err = ses:login()
            if not ok then
                self.status = nil
                self.error = err
                self.session = nil
            else
                self.session = ses
                self.error = nil
                self.status = nil
                ses:watch()      -- une partie déjà en cours sera reprise
                self:pump()
            end
            self:refresh("ui")
        end)
    end

    function Hub:pump()
        if self.closed or self.pumping_off then return end
        local ses = self.session
        if not ses then return end
        for _, ev in ipairs(ses:pump()) do
            if ev.kind == "gameStart" and not self.in_game then
                self.status = nil
                self:startGame(ev.id)
            elseif ev.kind == "seekError" then
                self.status = nil
                self.error = ev.text
                self:refresh("ui")
            end
        end
        if ses.state == "recherche" then
            local t = math.floor(ses.now() - (ses.seek_since or ses.now()))
            if t ~= self.shown_t and t % 5 == 0 then
                self.shown_t = t
                self:refresh("ui")
            end
        end
        if ses:active() and not self.in_game then
            UIManager:scheduleIn(0.5, function() self:pump() end)
        end
    end

    function Hub:startGame(id)
        local ses = self.session
        local g, err = ses:openGame(id)
        if not g then
            self.error = "Impossible d'ouvrir la partie (" .. tostring(err) .. ")."
            self:refresh("ui")
            return
        end
        self.in_game = true
        self.app:openOnlineGame(ses, function()
            self.in_game = false
            if self.closed then return end
            ses:closeGame()
            pcall(ses.login, ses)   -- classements à jour
            ses:watch()
            self:refresh("ui")
            self:pump()
        end)
    end

    function Hub:onClose()
        if self.session then self.session:closeAll() end
    end

    function Hub:askToken()
        local dialog
        dialog = InputDialog:new{
            title = "Clé Lichess",
            description = "Collez ou tapez la clé créée sur lichess.org (elle commence par « lip_ »).",
            input = "",
            buttons = { {
                { text = "Annuler", callback = function() UIManager:close(dialog) end },
                { text = "Enregistrer", is_enter_default = true, callback = function()
                    local t = (dialog:getInputText() or ""):gsub("%s", "")
                    UIManager:close(dialog)
                    if t ~= "" then
                        self.app:setLichessToken(t)
                        self:connect()
                    end
                end },
            } },
        }
        UIManager:show(dialog)
        dialog:onShowKeyboard()
    end

    function Hub:draw(bb)
        local app = self.app
        local W = self.W
        local m = s(20)
        local y = self:header(bb, "En ligne · Lichess", "Menu", function() self:close() end)
        y = y + s(16)
        local f, fb = UI.face(15), UI.face(16, true)
        local function para(text, face, color)
            for _, l in ipairs(UI.wrap(face, text, W - 2 * m)) do
                UI.text(bb, face, l, m, y, color)
                y = y + UI.lineHeight(face)
            end
        end
        local ses = self.session
        if not app:lichessToken() then
            para("Jouez contre de vrais joueurs sur Lichess, avec l'échiquier et la pendule de cette application.", f)
            y = y + s(14)
            UI.text(bb, fb, "À faire une seule fois", m, y)
            y = y + UI.lineHeight(fb) + s(4)
            para("1. Sur un ordinateur ou un téléphone, connectez-vous à lichess.org.", f, UI.DIM)
            para("2. Ouvrez lichess.org/account/oauth/token/create, cochez seulement « Jouer des parties avec l'API échiquier » et créez la clé.", f, UI.DIM)
            para("3. Copiez la clé dans un fichier texte nommé lichess_token.txt, placé sur la liseuse dans .adds/koreader/settings — ou tapez-la ici.", f, UI.DIM)
            y = y + s(8)
            para("Votre mot de passe Lichess n'est jamais demandé. La clé ne permet que de jouer, et vous pouvez la supprimer à tout moment sur lichess.org.", UI.face(13), UI.GRAY)
            y = y + s(20)
            local bw = s(240)
            UI.pill(bb, (W - bw) / 2, y, bw, s(46), "Saisir la clé", UI.face(17, true), { dark = true })
            self:region((W - bw) / 2, y, bw, s(46), function() self:askToken() end)
            return
        end
        if ses then
            UI.text(bb, UI.face(22, true), ses.username, m, y)
            y = y + UI.lineHeight(UI.face(22, true))
            local parts = {}
            for _, k in ipairs({ { "rapid", "Rapide" }, { "classical", "Classique" } }) do
                local p = ses.perfs[k[1]]
                if p then parts[#parts + 1] = k[2] .. " " .. p.rating .. (p.prov and "?" or "") end
            end
            UI.text(bb, UI.face(15), "Classements Lichess : " .. table.concat(parts, " · "), m, y, UI.DIM)
            y = y + s(40)
        end
        if self.status then
            para(self.status, fb)
            y = y + s(10)
        end
        if self.error then
            para(self.error, f)
            y = y + s(10)
        end
        if not ses then
            if not self.status then
                local bw = s(240)
                UI.pill(bb, m, y, bw, s(42), "Réessayer", UI.face(16), { dark = true })
                self:region(m, y, bw, s(42), function() self.error = nil; self:connect() end)
                local bw2 = s(240)
                UI.pill(bb, m + bw + s(12), y, bw2, s(42), "Changer de clé", UI.face(16))
                self:region(m + bw + s(12), y, bw2, s(42), function() self:askToken() end)
            end
            return
        end
        if ses.state == "recherche" then
            local t = math.floor(ses.now() - (ses.seek_since or ses.now()))
            UI.text(bb, UI.face(20, true), "Recherche d'un adversaire…", m, y)
            y = y + UI.lineHeight(UI.face(20, true)) + s(4)
            local c = Lichess.cadence(self.cadence)
            para(c.name .. (self.rated and " · partie classée" or " · partie amicale") .. " · depuis " .. t .. " s. "
                .. "L'échiquier s'ouvrira dès qu'un joueur est trouvé.", f, UI.DIM)
            y = y + s(20)
            local bw = s(200)
            UI.pill(bb, m, y, bw, s(44), "Annuler", UI.face(16))
            self:region(m, y, bw, s(44), function() ses:cancelSeek(); self:refresh("ui") end)
            return
        end
        UI.text(bb, fb, "Pendule", m, y)
        y = y + UI.lineHeight(fb) + s(4)
        local x = m
        for _, c in ipairs(Lichess.CADENCES) do
            local w = UI.textWidth(f, c.name) + s(36)
            if x + w > W - m then x = m; y = y + s(48) end
            UI.pill(bb, x, y, w, s(38), c.name, f, c.id == self.cadence and { dark = true } or {})
            self:region(x, y, w, s(38), function() self.cadence = c.id; self:refresh() end)
            x = x + w + s(10)
        end
        y = y + s(60)
        UI.text(bb, fb, "Type de partie", m, y)
        y = y + UI.lineHeight(fb) + s(4)
        x = m
        for _, o in ipairs({ { true, "Classée (compte pour votre Elo Lichess)" }, { false, "Amicale" } }) do
            local w = UI.textWidth(f, o[2]) + s(36)
            if x + w > W - m then x = m; y = y + s(48) end
            UI.pill(bb, x, y, w, s(38), o[2], f, o[1] == self.rated and { dark = true } or {})
            self:region(x, y, w, s(38), function() self.rated = o[1]; self:refresh() end)
            x = x + w + s(10)
        end
        y = y + s(66)
        local bw = s(330)
        UI.pill(bb, (W - bw) / 2, y, bw, s(50), "Chercher un adversaire", UI.face(18, true), { dark = true })
        self:region((W - bw) / 2, y, bw, s(50), function()
            app.profile.lichess_cadence, app.profile.lichess_rated = self.cadence, self.rated
            app:save()
            self.error = nil
            local ok, err = ses:seek(Lichess.cadence(self.cadence), self.rated)
            if not ok then self.error = err end
            self:refresh("ui")
            self:pump()
        end)
        y = y + s(76)
        para("Lichess n'autorise ici que les parties rapides et classiques (pas de blitz). "
            .. "Pendant une partie en ligne, le coach et Stockfish sont coupés : c'est la règle du jeu en ligne. "
            .. "Gardez la liseuse en Wi-Fi jusqu'à la fin de la partie.", UI.face(13), UI.GRAY)
        y = y + s(14)
        local lw = UI.textWidth(UI.face(14), "Changer de clé Lichess") + s(30)
        UI.pill(bb, m, y, lw, s(34), "Changer de clé Lichess", UI.face(14))
        self:region(m, y, lw, s(34), function() self:askToken() end)
    end

    -------------------------------------------------------------------
    -- La partie en ligne
    -------------------------------------------------------------------
    local Game = UI.Canvas:extend{ app = nil, session = nil, onDone = nil }
    Screens.Game = Game

    function Game:setup()
        local bs = math.min(self.W, self.H - 2 * s(56))
        bs = bs - bs % 8
        self.bs = bs
        self.board = Board:new{ size = bs }
        self.panel_h = math.floor((self.H - bs) / 2)
        self.mode = "normal"
        self.note = "Ouverture de la partie…"
        pcall(function() UIManager:preventStandby() end)
        self.standby = true
        self:pump()
        self:tick()
    end

    function Game:g() return self.session.game end

    function Game:onClose()
        if self.standby then pcall(function() UIManager:allowStandby() end) end
        self.standby = false
        if self.onDone then self.onDone() end
    end

    function Game:pump()
        if self.closed then return end
        local ses = self.session
        local changed = false
        for _, ev in ipairs(ses:pump()) do
            if ev.kind == "game" then
                changed = true
                if ev.type == "gameFull" or ev.type == "gameState" then self.note = nil end
            elseif ev.kind == "reconnect" then
                self.note = "Connexion perdue, reconnexion…"
                changed = true
            elseif ev.kind == "gameError" then
                self.note = ev.text
                changed = true
            end
        end
        local g = self:g()
        if changed then
            if g and g:ended() then self.mode = "normal"; self.selected, self.targets = nil, nil end
            self:refresh("ui")
        end
        -- la liseuse ne doit pas s'endormir en attendant le coup de l'adversaire
        local t = os.time()
        if g and not g:ended() and (not self.awake or t - self.awake >= 30) then
            self.awake = t
            pcall(function() UIManager:broadcastEvent(require("ui/event"):new("InputEvent")) end)
        end
        -- on regarde plus souvent quand on attend le coup de l'adversaire
        local waiting = g and g.loaded and not g:ended() and not g:myTurn()
        if ses:active() then UIManager:scheduleIn(waiting and 0.15 or 0.4, function() self:pump() end) end
    end

    function Game:tick()
        if self.closed then return end
        local g = self:g()
        if g and g:clockRunning() then
            local c = g.positions[#g.positions].turn
            local r = self.clock_rect and self.clock_rect[c]
            if r then self:refresh("fast", Geom:new{ x = r.x, y = r.y, w = r.w, h = r.h }) end
            local t = g:time(c)
            UIManager:scheduleIn(t < 10 and 0.25 or 1, function() self:tick() end)
        else
            UIManager:scheduleIn(1, function() self:tick() end)
        end
    end

    -- Bande d'un joueur : pendule, nom et classement ; boutons pour le joueur (en bas)
    function Game:drawStrip(bb, y, h, color, mine)
        local g = self:g()
        local W = self.W
        local m = s(12)
        local bh = s(38)
        local cy = y + math.floor((h - bh) / 2)
        local t = g:time(color)
        local active = g:clockRunning() and g.positions[#g.positions].turn == color
        local low = t < 30
        local cf = UI.face(18, true)
        local cw = s(108)
        local r = math.floor(bh / 2)
        if active and low then Draw.roundedRect(bb, m, cy, cw, bh, r, UI.RED, 0x90)
        elseif active then Draw.roundedRect(bb, m, cy, cw, bh, r, nil, 0x00)
        else bb:paintBorder(m, cy, cw, bh, s(1), UI.BLACK, r) end
        UI.textCentered(bb, cf, fmtClock(t), m + cw / 2, cy + (bh - UI.lineHeight(cf)) / 2 + s(2),
            (active and not low) and UI.WHITE or UI.BLACK)
        self.clock_rect[color] = { x = m, y = cy, w = cw, h = bh }
        local x = m + cw + s(12)
        local f = UI.face(14)
        -- différence de matériel : « +3 » à côté de la pendule du camp qui a plus de matériel
        local pos = g:pos()
        local diff = pos:material(color) - pos:material(color == "w" and "b" or "w")
        if diff > 0 then
            local df = UI.face(18, true)
            local dw = UI.text(bb, df, "+" .. diff, x, cy + (bh - UI.lineHeight(df)) / 2 + s(2))
            x = x + dw + s(12)
        end

        local items = {}
        local label
        if mine then
            local opp = color == "w" and "b" or "w"
            local ses = self.session
            local function act(fn, failText)
                return function()
                    local ok, err = fn()
                    if not ok then info((failText or "Action refusée") .. " : " .. tostring(err)) end
                    self.mode = "normal"
                    self:refresh("ui")
                end
            end
            if g:ended() then
                label = g:resultText()
                items = { { "Nouvelle partie", function() self:close() end, true } }
            elseif self.mode == "abandon" then
                label = #g.moves < 2 and "Annuler la partie ?" or "Abandonner ?"
                items = {
                    { "Oui", act(function()
                        if #g.moves < 2 then return ses:abort() end
                        return ses:resign()
                    end), true },
                    { "Non", function() self.mode = "normal"; self:refresh("ui") end },
                }
            elseif g.draw_offer and g.draw_offer[opp] then
                label = "Nulle proposée :"
                items = {
                    { "Accepter", act(function() return ses:draw(true) end), true },
                    { "Refuser", act(function() return ses:draw(false) end) },
                }
            elseif g.gone and g.claim_in and g.now() - (g.gone_stamp or 0) >= g.claim_in then
                label = "Adversaire parti :"
                items = { { "Réclamer la victoire", act(function() return ses:claimVictory() end), true } }
            else
                if self.note then label = self.note
                elseif g.pending then label = "Envoi du coup…"
                elseif g:myTurn() then label = g:pos():inCheck() and "Échec ! À vous" or "À vous de jouer"
                elseif g.gone then label = "Adversaire déconnecté…"
                else label = g.loaded and "L'adversaire réfléchit" or "Ouverture…" end
                if g.draw_offer and g.draw_offer[color] then label = "Nulle proposée" end
                items = {
                    { "Nulle", act(function() return ses:draw(true) end), false, #g.moves < 2 },
                    { #g.moves < 2 and "Annuler" or "Abandon", function() self.mode = "abandon"; self:refresh("ui") end },
                }
            end
            items[#items + 1] = { "Fermer", function() self:askClose() end }
        else
            local p = g.players[color]
            label = (p.title and (p.title .. " ") or "") .. (p.name or "Adversaire") .. (p.rating and (" (" .. p.rating .. ")") or "")
            if g.rated ~= nil then label = label .. (g.rated and " · classée" or " · amicale") end
        end
        local widths, total = {}, 0
        for i, it in ipairs(items) do
            widths[i] = UI.textWidth(f, it[1]) + s(24)
            total = total + widths[i] + s(8)
        end
        local bx = W - m - total + s(8)
        if #items == 0 then bx = W - m end
        local nf = UI.face(15, mine and g:ended())
        UI.text(bb, nf, UI.ellipsize(nf, label or "", math.max(s(40), bx - x - s(8))), x, cy + (bh - UI.lineHeight(nf)) / 2 + s(2))
        for i, it in ipairs(items) do
            local dis = it[4]
            UI.pill(bb, bx, cy, widths[i], bh, it[1], f, it[3] and { dark = true } or (dis and { disabled = true } or {}))
            if not dis then self:region(bx, cy - s(6), widths[i], bh + s(12), it[2]) end
            bx = bx + widths[i] + s(8)
        end
    end

    function Game:askClose()
        local g = self:g()
        if not g or g:ended() or not g.loaded then return self:close() end
        UIManager:show(ConfirmBox:new{
            text = "La partie continue sur Lichess et votre pendule tourne. Fermer quand même ? (Vous pourrez la reprendre depuis « En ligne ».)",
            ok_text = "Fermer", cancel_text = "Rester", ok_callback = function() self:close() end,
        })
    end

    function Game:draw(bb)
        local g = self:g()
        local W, ph = self.W, self.panel_h
        self.clock_rect = {}
        if not g then return end
        local me = g.me or "w"
        local opp = me == "w" and "b" or "w"
        self:drawStrip(bb, 0, ph, opp, false)
        local wy = ph + self.bs
        self:drawStrip(bb, wy, self.H - wy, me, true)
        local b = self.board
        b.pos = g:pos()
        b.flipped = me == "b"
        b.last_move = g:lastMove()
        b.selected, b.targets = self.selected, self.targets
        b.arrows, b.marks, b.badges = {}, {}, {}
        local bx = math.floor((W - self.bs) / 2)
        b:paintTo(bb, bx, ph)
        self:region(bx, ph, self.bs, self.bs, function(ges)
            local sq = b:squareAt(ges.pos.x, ges.pos.y)
            if sq then self:onSquare(sq) end
        end)
    end

    function Game:send(mv)
        local g = self:g()
        local uci = Chess.moveToUci(mv)
        g:setPending(mv)
        self.selected, self.targets = nil, nil
        self.note = nil
        self:refresh("ui")
        -- l'envoi bloque une seconde ou deux : on laisse d'abord l'écran afficher le coup
        UIManager:nextTick(function()
            if self.closed then return end
            local ok, err = self.session:move(uci)
            if not ok then
                g:clearPending()
                self.note = "Coup non envoyé (" .. tostring(err) .. "). Rejouez-le."
                self:refresh("ui")
            end
        end)
    end

    function Game:onSquare(sq)
        local g = self:g()
        if not g or not g:myTurn() then return end
        local pos = g:pos()
        if self.selected and self.targets and self.targets[sq] then
            local cands = {}
            for _, mv in ipairs(pos:legalMovesFrom(self.selected)) do
                if mv.to == sq then cands[#cands + 1] = mv end
            end
            if #cands > 1 then
                local dialog
                local names = { q = "Dame", r = "Tour", b = "Fou", n = "Cavalier" }
                local row = {}
                for _, pr in ipairs({ "q", "r", "b", "n" }) do
                    for _, mv in ipairs(cands) do
                        if mv.promo == pr then
                            row[#row + 1] = { text = names[pr], callback = function()
                                UIManager:close(dialog)
                                self:send(mv)
                            end }
                        end
                    end
                end
                dialog = ButtonDialog:new{ title = "Promotion du pion", buttons = { row } }
                UIManager:show(dialog)
            elseif #cands == 1 then
                self:send(cands[1])
            end
            return
        end
        local p = pos.board[sq]
        if p and Chess.colorOf(p) == pos.turn and sq ~= self.selected then
            self.selected = sq
            self.targets = {}
            for _, mv in ipairs(pos:legalMovesFrom(sq)) do self.targets[mv.to] = true end
        else
            self.selected, self.targets = nil, nil
        end
        self:refresh("ui")
    end

    return Screens
end

return Lichess
