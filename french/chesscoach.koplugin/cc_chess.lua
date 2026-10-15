--[[
  Règles des échecs (pur Lua, sans dépendance).
  Cases numérotées 0..63 : a1 = 0, h1 = 7, a8 = 56, h8 = 63.
  Pièces : majuscules = blancs (PNBRQK), minuscules = noirs.
]]

local Chess = {}
Chess.__index = Chess

local START_FEN = "rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1"
Chess.START_FEN = START_FEN

local FILES = "abcdefgh"

local function sqName(sq)
    local f = sq % 8
    local r = math.floor(sq / 8)
    return FILES:sub(f + 1, f + 1) .. tostring(r + 1)
end
Chess.sqName = sqName

local function sqFromName(name)
    local f = FILES:find(name:sub(1, 1), 1, true)
    local r = tonumber(name:sub(2, 2))
    if not f or not r then return nil end
    return (r - 1) * 8 + (f - 1)
end
Chess.sqFromName = sqFromName

local function fileOf(sq) return sq % 8 end
local function rankOf(sq) return math.floor(sq / 8) end
Chess.fileOf = fileOf
Chess.rankOf = rankOf

local function colorOf(p)
    if not p then return nil end
    if p == p:upper() then return "w" end
    return "b"
end
Chess.colorOf = colorOf

local function other(c) return c == "w" and "b" or "w" end
Chess.other = other

Chess.VALUES = { p = 1, n = 3, b = 3, r = 5, q = 9, k = 0 }

local KNIGHT = { {1,2},{2,1},{2,-1},{1,-2},{-1,-2},{-2,-1},{-2,1},{-1,2} }
local KING   = { {1,0},{1,1},{0,1},{-1,1},{-1,0},{-1,-1},{0,-1},{1,-1} }
local BISHOP = { {1,1},{1,-1},{-1,1},{-1,-1} }
local ROOK   = { {1,0},{-1,0},{0,1},{0,-1} }

local function offset(sq, df, dr)
    local f = fileOf(sq) + df
    local r = rankOf(sq) + dr
    if f < 0 or f > 7 or r < 0 or r > 7 then return nil end
    return r * 8 + f
end
Chess.offset = offset

---------------------------------------------------------------------------
-- Création / FEN
---------------------------------------------------------------------------

function Chess.new(fen)
    local self = setmetatable({}, Chess)
    self:loadFen(fen or START_FEN)
    return self
end

function Chess:loadFen(fen)
    local parts = {}
    for p in fen:gmatch("%S+") do parts[#parts + 1] = p end
    self.board = {}
    local rank, file = 7, 0
    for c in parts[1]:gmatch(".") do
        if c == "/" then
            rank = rank - 1
            file = 0
        elseif c:match("%d") then
            file = file + tonumber(c)
        else
            self.board[rank * 8 + file] = c
            file = file + 1
        end
    end
    self.turn = parts[2] or "w"
    local cas = parts[3] or "-"
    self.castling = {
        K = cas:find("K", 1, true) ~= nil,
        Q = cas:find("Q", 1, true) ~= nil,
        k = cas:find("k", 1, true) ~= nil,
        q = cas:find("q", 1, true) ~= nil,
    }
    local ep = parts[4] or "-"
    self.ep = (ep ~= "-") and sqFromName(ep) or nil
    self.halfmove = tonumber(parts[5] or "0") or 0
    self.fullmove = tonumber(parts[6] or "1") or 1
end

function Chess:fen()
    local rows = {}
    for r = 7, 0, -1 do
        local row, empty = "", 0
        for f = 0, 7 do
            local p = self.board[r * 8 + f]
            if p then
                if empty > 0 then row = row .. empty; empty = 0 end
                row = row .. p
            else
                empty = empty + 1
            end
        end
        if empty > 0 then row = row .. empty end
        rows[#rows + 1] = row
    end
    local cas = ""
    if self.castling.K then cas = cas .. "K" end
    if self.castling.Q then cas = cas .. "Q" end
    if self.castling.k then cas = cas .. "k" end
    if self.castling.q then cas = cas .. "q" end
    if cas == "" then cas = "-" end
    -- On n'écrit la case en passant que si une prise en passant est réellement possible
    local ep = "-"
    if self.ep then
        local pawn = self.turn == "w" and "P" or "p"
        local dr = self.turn == "w" and -1 or 1
        for _, df in ipairs({-1, 1}) do
            local s = offset(self.ep, df, dr)
            if s and self.board[s] == pawn then ep = sqName(self.ep) end
        end
    end
    return table.concat(rows, "/") .. " " .. self.turn .. " " .. cas .. " " .. ep
        .. " " .. self.halfmove .. " " .. self.fullmove
end

-- Clé de répétition (sans les compteurs)
function Chess:key()
    local f = self:fen()
    return (f:match("^(%S+ %S+ %S+ %S+)"))
end

function Chess:clone()
    local c = setmetatable({}, Chess)
    c.board = {}
    for k, v in pairs(self.board) do c.board[k] = v end
    c.turn = self.turn
    c.castling = { K = self.castling.K, Q = self.castling.Q, k = self.castling.k, q = self.castling.q }
    c.ep = self.ep
    c.halfmove = self.halfmove
    c.fullmove = self.fullmove
    return c
end

---------------------------------------------------------------------------
-- Attaques
---------------------------------------------------------------------------

-- Liste des cases depuis lesquelles une pièce de couleur `by` attaque `sq`
function Chess:attackersOf(sq, by)
    local list = {}
    local b = self.board
    local isW = by == "w"
    -- pions
    local pr = isW and -1 or 1
    for _, df in ipairs({-1, 1}) do
        local s = offset(sq, df, pr)
        if s and b[s] == (isW and "P" or "p") then list[#list + 1] = s end
    end
    for _, d in ipairs(KNIGHT) do
        local s = offset(sq, d[1], d[2])
        if s and b[s] == (isW and "N" or "n") then list[#list + 1] = s end
    end
    for _, d in ipairs(KING) do
        local s = offset(sq, d[1], d[2])
        if s and b[s] == (isW and "K" or "k") then list[#list + 1] = s end
    end
    local function slide(dirs, a, c)
        for _, d in ipairs(dirs) do
            local s = offset(sq, d[1], d[2])
            while s do
                local p = b[s]
                if p then
                    if colorOf(p) == by then
                        local l = p:lower()
                        if l == a or l == c then list[#list + 1] = s end
                    end
                    break
                end
                s = offset(s, d[1], d[2])
            end
        end
    end
    slide(BISHOP, "b", "q")
    slide(ROOK, "r", "q")
    return list
end

function Chess:isAttacked(sq, by)
    return #self:attackersOf(sq, by) > 0
end

function Chess:kingSquare(color)
    local k = color == "w" and "K" or "k"
    for s = 0, 63 do
        if self.board[s] == k then return s end
    end
    return nil
end

function Chess:inCheck(color)
    color = color or self.turn
    local ks = self:kingSquare(color)
    if not ks then return false end
    return self:isAttacked(ks, other(color))
end

-- Cases attaquées par la pièce placée en `sq` (pour le coach)
function Chess:attacksFrom(sq)
    local p = self.board[sq]
    if not p then return {} end
    local c = colorOf(p)
    local l = p:lower()
    local res = {}
    local b = self.board
    if l == "p" then
        local dr = c == "w" and 1 or -1
        for _, df in ipairs({-1, 1}) do
            local s = offset(sq, df, dr)
            if s then res[#res + 1] = s end
        end
    elseif l == "n" or l == "k" then
        for _, d in ipairs(l == "n" and KNIGHT or KING) do
            local s = offset(sq, d[1], d[2])
            if s then res[#res + 1] = s end
        end
    else
        local dirs = {}
        if l == "b" or l == "q" then for _, d in ipairs(BISHOP) do dirs[#dirs + 1] = d end end
        if l == "r" or l == "q" then for _, d in ipairs(ROOK) do dirs[#dirs + 1] = d end end
        for _, d in ipairs(dirs) do
            local s = offset(sq, d[1], d[2])
            while s do
                res[#res + 1] = s
                if b[s] then break end
                s = offset(s, d[1], d[2])
            end
        end
    end
    return res
end

---------------------------------------------------------------------------
-- Génération des coups
---------------------------------------------------------------------------

local function addMove(list, from, to, piece, captured, extra)
    local m = { from = from, to = to, piece = piece, captured = captured }
    if extra then for k, v in pairs(extra) do m[k] = v end end
    list[#list + 1] = m
end

function Chess:pseudoMoves()
    local moves = {}
    local b = self.board
    local us = self.turn
    local them = other(us)
    for sq = 0, 63 do
        local p = b[sq]
        if p and colorOf(p) == us then
            local l = p:lower()
            if l == "p" then
                local dr = us == "w" and 1 or -1
                local startRank = us == "w" and 1 or 6
                local promoRank = us == "w" and 7 or 0
                local one = offset(sq, 0, dr)
                if one and not b[one] then
                    if rankOf(one) == promoRank then
                        for _, pr in ipairs({"q", "r", "b", "n"}) do
                            addMove(moves, sq, one, p, nil, { promo = pr })
                        end
                    else
                        addMove(moves, sq, one, p, nil)
                        if rankOf(sq) == startRank then
                            local two = offset(sq, 0, 2 * dr)
                            if two and not b[two] then addMove(moves, sq, two, p, nil, { double = true }) end
                        end
                    end
                end
                for _, df in ipairs({-1, 1}) do
                    local t = offset(sq, df, dr)
                    if t then
                        local tp = b[t]
                        if tp and colorOf(tp) == them then
                            if rankOf(t) == promoRank then
                                for _, pr in ipairs({"q", "r", "b", "n"}) do
                                    addMove(moves, sq, t, p, tp, { promo = pr })
                                end
                            else
                                addMove(moves, sq, t, p, tp)
                            end
                        elseif self.ep and t == self.ep then
                            addMove(moves, sq, t, p, us == "w" and "p" or "P", { enpassant = true })
                        end
                    end
                end
            elseif l == "n" or l == "k" then
                for _, d in ipairs(l == "n" and KNIGHT or KING) do
                    local t = offset(sq, d[1], d[2])
                    if t then
                        local tp = b[t]
                        if not tp or colorOf(tp) == them then addMove(moves, sq, t, p, tp) end
                    end
                end
                if l == "k" then
                    -- Roque
                    local home = us == "w" and 4 or 60
                    if sq == home and not self:isAttacked(home, them) then
                        local kc = us == "w" and "K" or "k"
                        local qc = us == "w" and "Q" or "q"
                        local rook = us == "w" and "R" or "r"
                        if self.castling[kc] and b[home + 3] == rook and not b[home + 1] and not b[home + 2]
                            and not self:isAttacked(home + 1, them) and not self:isAttacked(home + 2, them) then
                            addMove(moves, home, home + 2, p, nil, { castle = "K" })
                        end
                        if self.castling[qc] and b[home - 4] == rook and not b[home - 1] and not b[home - 2]
                            and not b[home - 3]
                            and not self:isAttacked(home - 1, them) and not self:isAttacked(home - 2, them) then
                            addMove(moves, home, home - 2, p, nil, { castle = "Q" })
                        end
                    end
                end
            else
                local dirs = {}
                if l == "b" or l == "q" then for _, d in ipairs(BISHOP) do dirs[#dirs + 1] = d end end
                if l == "r" or l == "q" then for _, d in ipairs(ROOK) do dirs[#dirs + 1] = d end end
                for _, d in ipairs(dirs) do
                    local t = offset(sq, d[1], d[2])
                    while t do
                        local tp = b[t]
                        if tp then
                            if colorOf(tp) == them then addMove(moves, sq, t, p, tp) end
                            break
                        end
                        addMove(moves, sq, t, p, nil)
                        t = offset(t, d[1], d[2])
                    end
                end
            end
        end
    end
    return moves
end

-- Applique un coup et renvoie une NOUVELLE position
function Chess:makeMove(m)
    local n = self:clone()
    local b = n.board
    local us = self.turn
    local p = b[m.from]
    b[m.from] = nil
    if m.enpassant then
        local cap = us == "w" and m.to - 8 or m.to + 8
        b[cap] = nil
    end
    if m.promo then
        p = us == "w" and m.promo:upper() or m.promo:lower()
    end
    b[m.to] = p
    if m.castle then
        local home = us == "w" and 4 or 60
        if m.castle == "K" then
            b[home + 1] = b[home + 3]; b[home + 3] = nil
        else
            b[home - 1] = b[home - 4]; b[home - 4] = nil
        end
    end
    -- droits de roque
    local function touch(sq)
        if sq == 4 then n.castling.K = false; n.castling.Q = false end
        if sq == 60 then n.castling.k = false; n.castling.q = false end
        if sq == 0 then n.castling.Q = false end
        if sq == 7 then n.castling.K = false end
        if sq == 56 then n.castling.q = false end
        if sq == 63 then n.castling.k = false end
    end
    touch(m.from); touch(m.to)
    n.ep = nil
    if m.double then n.ep = us == "w" and m.from + 8 or m.from - 8 end
    if m.piece:lower() == "p" or m.captured then n.halfmove = 0 else n.halfmove = self.halfmove + 1 end
    if us == "b" then n.fullmove = self.fullmove + 1 end
    n.turn = other(us)
    return n
end

function Chess:legalMoves()
    local res = {}
    local us = self.turn
    for _, m in ipairs(self:pseudoMoves()) do
        local n = self:makeMove(m)
        if not n:inCheck(us) then res[#res + 1] = m end
    end
    return res
end

function Chess:legalMovesFrom(sq)
    local res = {}
    for _, m in ipairs(self:legalMoves()) do
        if m.from == sq then res[#res + 1] = m end
    end
    return res
end

---------------------------------------------------------------------------
-- Notation
---------------------------------------------------------------------------

function Chess.moveToUci(m)
    return sqName(m.from) .. sqName(m.to) .. (m.promo or "")
end

function Chess:findUci(uci)
    if not uci or #uci < 4 then return nil end
    local from = sqFromName(uci:sub(1, 2))
    local to = sqFromName(uci:sub(3, 4))
    local promo = uci:sub(5, 5)
    if promo == "" then promo = nil end
    for _, m in ipairs(self:legalMoves()) do
        if m.from == from and m.to == to and (m.promo == promo) then return m end
    end
    return nil
end

-- Lettres françaises : R(oi) D(ame) T(our) F(ou) C(avalier)
local FR_LETTER = { k = "R", q = "D", r = "T", b = "F", n = "C", p = "" }
Chess.FR_LETTER = FR_LETTER

function Chess:san(m)
    local s
    if m.castle == "K" then
        s = "O-O"
    elseif m.castle == "Q" then
        s = "O-O-O"
    else
        local l = m.piece:lower()
        s = FR_LETTER[l]
        if l == "p" then
            if m.captured then s = FILES:sub(fileOf(m.from) + 1, fileOf(m.from) + 1) .. "x" end
        else
            -- désambiguïsation
            local sameFile, sameRank, ambiguous = false, false, false
            for _, o in ipairs(self:legalMoves()) do
                if o.to == m.to and o.from ~= m.from and o.piece == m.piece then
                    ambiguous = true
                    if fileOf(o.from) == fileOf(m.from) then sameFile = true end
                    if rankOf(o.from) == rankOf(m.from) then sameRank = true end
                end
            end
            if ambiguous then
                if not sameFile then
                    s = s .. FILES:sub(fileOf(m.from) + 1, fileOf(m.from) + 1)
                elseif not sameRank then
                    s = s .. tostring(rankOf(m.from) + 1)
                else
                    s = s .. sqName(m.from)
                end
            end
            if m.captured then s = s .. "x" end
        end
        s = s .. sqName(m.to)
        if m.promo then s = s .. "=" .. FR_LETTER[m.promo] end
    end
    local n = self:makeMove(m)
    if n:inCheck() then
        if #n:legalMoves() == 0 then s = s .. "#" else s = s .. "+" end
    end
    return s
end

---------------------------------------------------------------------------
-- Fin de partie
---------------------------------------------------------------------------

function Chess:insufficientMaterial()
    local minors, others = {}, 0
    for s = 0, 63 do
        local p = self.board[s]
        if p then
            local l = p:lower()
            if l == "b" or l == "n" then
                minors[#minors + 1] = { l = l, sq = s }
            elseif l ~= "k" then
                others = others + 1
            end
        end
    end
    if others > 0 then return false end
    if #minors <= 1 then return true end
    -- uniquement des fous sur la même couleur de case
    local color
    for _, m in ipairs(minors) do
        if m.l ~= "b" then return false end
        local c = (fileOf(m.sq) + rankOf(m.sq)) % 2
        if color == nil then color = c elseif color ~= c then return false end
    end
    return true
end

-- Renvoie nil si la partie continue, sinon { result = "1-0"|"0-1"|"1/2-1/2", reason = "..." }
function Chess:status(repetitionCount)
    local moves = self:legalMoves()
    if #moves == 0 then
        if self:inCheck() then
            return { result = self.turn == "w" and "0-1" or "1-0", reason = "échec et mat" }
        end
        return { result = "1/2-1/2", reason = "pat" }
    end
    if self:insufficientMaterial() then return { result = "1/2-1/2", reason = "matériel insuffisant" } end
    if self.halfmove >= 100 then return { result = "1/2-1/2", reason = "règle des 50 coups" } end
    if repetitionCount and repetitionCount >= 3 then return { result = "1/2-1/2", reason = "triple répétition" } end
    return nil
end

function Chess:material(color)
    local t = 0
    for s = 0, 63 do
        local p = self.board[s]
        if p and colorOf(p) == color then t = t + Chess.VALUES[p:lower()] end
    end
    return t
end

---------------------------------------------------------------------------
-- Coups anticipés : cases que la pièce pourrait atteindre « en théorie »
-- (sans tenir compte des pièces qui bloquent), comme sur les sites d'échecs
---------------------------------------------------------------------------

function Chess:premoveTargets(sq)
    local p = self.board[sq]
    if not p then return {} end
    local c = colorOf(p)
    local l = p:lower()
    local res = {}
    local function add(t)
        if t then
            local q = self.board[t]
            if not q or colorOf(q) ~= c or true then res[t] = true end
        end
    end
    if l == "p" then
        local dr = c == "w" and 1 or -1
        add(offset(sq, 0, dr))
        if rankOf(sq) == (c == "w" and 1 or 6) then add(offset(sq, 0, 2 * dr)) end
        add(offset(sq, -1, dr)); add(offset(sq, 1, dr))
    elseif l == "n" or l == "k" then
        for _, d in ipairs(l == "n" and KNIGHT or KING) do add(offset(sq, d[1], d[2])) end
        if l == "k" then
            local home = c == "w" and 4 or 60
            if sq == home then
                if self.castling[c == "w" and "K" or "k"] then add(home + 2) end
                if self.castling[c == "w" and "Q" or "q"] then add(home - 2) end
            end
        end
    else
        local dirs = {}
        if l == "b" or l == "q" then for _, d in ipairs(BISHOP) do dirs[#dirs + 1] = d end end
        if l == "r" or l == "q" then for _, d in ipairs(ROOK) do dirs[#dirs + 1] = d end end
        for _, d in ipairs(dirs) do
            local t = offset(sq, d[1], d[2])
            while t do add(t); t = offset(t, d[1], d[2]) end
        end
    end
    res[sq] = nil
    return res
end

---------------------------------------------------------------------------
-- Test de validité (perft)
---------------------------------------------------------------------------

function Chess:perft(depth)
    if depth == 0 then return 1 end
    local n = 0
    for _, m in ipairs(self:legalMoves()) do
        n = n + self:makeMove(m):perft(depth - 1)
    end
    return n
end

return Chess
