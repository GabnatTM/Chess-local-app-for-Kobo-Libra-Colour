--[[
  Stockfish driver.
  Stockfish is started for each analysis with a small command file.
  Asynchronous mode (on the reader): the program runs in the background
  and we watch its output file, so the screen stays responsive.
  Synchronous mode (tests on a computer): we simply wait for it to finish.
]]

local Engine = {}
Engine.__index = Engine

local function fileExists(p)
    local f = io.open(p, "r")
    if f then f:close() return true end
    return false
end

local function readAll(p)
    local f = io.open(p, "r")
    if not f then return nil end
    local s = f:read("*a")
    f:close()
    return s
end

local function shellQuote(s)
    return "'" .. tostring(s):gsub("'", "'\\''") .. "'"
end

--[[
  opts = {
    bin = path to stockfish,
    tmp = temporary folder,
    schedule = function(seconds, fn)  -- nil = synchronous mode
    threads = 1, hash = 16
  }
]]
function Engine.new(opts)
    local self = setmetatable({}, Engine)
    self.bin = opts.bin
    self.tmp = opts.tmp or "/tmp"
    self.schedule = opts.schedule
    self.threads = opts.threads or 1
    self.hash = opts.hash or 16
    self.queue = {}
    self.busy = false
    self.job_id = 0
    self.generation = 0
    return self
end

-- Checks that Stockfish starts; otherwise copies it to /tmp and makes it executable.
function Engine:ensureRunnable()
    if self.checked then return self.ok end
    self.checked = true
    local function test(bin)
        local inp = self.tmp .. "/chesscircuit_test.in"
        local out = self.tmp .. "/chesscircuit_test.out"
        local f = io.open(inp, "w")
        if not f then return false end
        f:write("uci\n")
        f:close()
        os.execute(shellQuote(bin) .. " < " .. shellQuote(inp) .. " > " .. shellQuote(out) .. " 2>/dev/null")
        local s = readAll(out) or ""
        os.remove(inp); os.remove(out)
        return s:find("uciok", 1, true) ~= nil
    end
    if fileExists(self.bin) and test(self.bin) then
        self.ok = true
        return true
    end
    if fileExists(self.bin) then
        local copy = self.tmp .. "/chesscircuit_stockfish"
        os.execute("cp " .. shellQuote(self.bin) .. " " .. shellQuote(copy) .. " && chmod 755 " .. shellQuote(copy))
        if test(copy) then
            self.bin = copy
            self.ok = true
            return true
        end
    end
    self.ok = false
    return false
end

-- Reads the UCI output and returns the analysis lines (from the side to move's point of view)
local function parseOutput(text)
    local lines = {}
    local bestmove
    for line in text:gmatch("[^\r\n]+") do
        if line:sub(1, 5) == "info " and line:find(" pv ", 1, true) then
            local depth = tonumber(line:match(" depth (%d+)"))
            local mpv = tonumber(line:match(" multipv (%d+)")) or 1
            local cp = tonumber(line:match(" score cp (%-?%d+)"))
            local mate = tonumber(line:match(" score mate (%-?%d+)"))
            local bound = line:match(" (lowerbound)") or line:match(" (upperbound)")
            local pvs = line:match(" pv (.+)$")
            if pvs and not bound then
                local pv = {}
                for mv in pvs:gmatch("%S+") do pv[#pv + 1] = mv end
                local score
                if mate then
                    if mate > 0 then score = 10000 - mate * 10 else score = -10000 - mate * 10 end
                else
                    score = cp or 0
                end
                local prev = lines[mpv]
                if not prev or (depth or 0) >= (prev.depth or 0) then
                    lines[mpv] = { multipv = mpv, depth = depth, cp = score, mate = mate, pv = pv, move = pv[1] }
                end
            end
        elseif line:sub(1, 9) == "bestmove " then
            bestmove = line:match("^bestmove (%S+)")
        end
    end
    local res = {}
    for i = 1, #lines do
        if lines[i] then res[#res + 1] = lines[i] end
    end
    return res, bestmove
end
Engine.parseOutput = parseOutput

function Engine:_writeInput(path, fen, multipv, movetime)
    local f = io.open(path, "w")
    if not f then return false end
    f:write("setoption name Threads value " .. self.threads .. "\n")
    f:write("setoption name Hash value " .. self.hash .. "\n")
    f:write("setoption name MultiPV value " .. multipv .. "\n")
    f:write("isready\n")
    f:write("position fen " .. fen .. "\n")
    f:write("go movetime " .. math.floor(movetime) .. "\n")
    f:close()
    return true
end

--[[
  Analyses a position.
  callback(lines, bestmove); lines[1] = best line.
  Jobs are queued: only one Stockfish runs at a time.
]]
function Engine:analyse(fen, multipv, movetime, callback)
    self.queue[#self.queue + 1] = { fen = fen, multipv = multipv or 1, movetime = movetime or 1000,
        callback = callback, generation = self.generation }
    self:_next()
end

-- Cancels pending analyses (new game, takeback…)
function Engine:cancelAll()
    self.generation = self.generation + 1
    self.queue = {}
end

function Engine:_next()
    if self.busy or #self.queue == 0 then return end
    local job = table.remove(self.queue, 1)
    if job.generation ~= self.generation then return self:_next() end
    self.busy = true
    self.job_id = self.job_id + 1
    local inp = self.tmp .. "/chesscircuit_" .. self.job_id .. ".in"
    local out = self.tmp .. "/chesscircuit_" .. self.job_id .. ".out"
    self:_writeInput(inp, job.fen, job.multipv, job.movetime)

    local function finish(text)
        os.remove(inp); os.remove(out)
        self.busy = false
        local lines, best = parseOutput(text or "")
        if job.generation == self.generation and job.callback then
            job.callback(lines, best)
        end
        self:_next()
    end

    local cmd = shellQuote(self.bin) .. " < " .. shellQuote(inp) .. " > " .. shellQuote(out) .. " 2>/dev/null"
    if not self.schedule then
        os.execute(cmd)
        finish(readAll(out))
        return
    end
    os.execute(cmd .. " &")
    local waited = 0
    local limit = job.movetime / 1000 + 15
    local function poll()
        local text = readAll(out)
        if text and text:find("bestmove", 1, true) then
            finish(text)
            return
        end
        waited = waited + 0.25
        if waited > limit then
            finish(text)
            return
        end
        self.schedule(0.25, poll)
    end
    self.schedule(math.max(0.2, job.movetime / 1000), poll)
end

return Engine
