--[[
  Chess Circuit — a chess game for KOReader: coach, tournaments, casual games.
  Adds "Chess Circuit" to the Tools menu.
]]

local DataStorage = require("datastorage")
local Dispatcher = require("dispatcher")
local InfoMessage = require("ui/widget/infomessage")
local LuaSettings = require("luasettings")
local UIManager = require("ui/uimanager")
local WidgetContainer = require("ui/widget/container/widgetcontainer")
local logger = require("logger")
local _ = require("gettext")

-- Plugin modules (loaded here, while the plugin folder is in the path)
local Engine = require("cc_engine")
local App = require("cc_app")

local ok_time, time = pcall(require, "ui/time")

local ChessCircuit = WidgetContainer:extend{
    name = "chesscircuit",
    is_doc_only = false,
}

function ChessCircuit:onDispatcherRegisterActions()
    Dispatcher:registerAction("chesscircuit_open", {
        category = "none", event = "OpenChessCircuit", title = _("Chess Circuit"), general = true,
    })
end

function ChessCircuit:init()
    self:onDispatcherRegisterActions()
    self.ui.menu:registerToMainMenu(self)
end

function ChessCircuit:addToMainMenu(menu_items)
    menu_items.chesscircuit = {
        text = _("Chess Circuit"),
        sorting_hint = "tools",
        callback = function() self:open() end,
    }
end

function ChessCircuit:onOpenChessCircuit()
    self:open()
    return true
end

local function tmpDir()
    local f = io.open("/tmp/.chesscircuit_w", "w")
    if f then
        f:close()
        os.remove("/tmp/.chesscircuit_w")
        return "/tmp"
    end
    return DataStorage:getDataDir()
end

local function monotonic()
    if ok_time and time and time.monotonic then
        return time.to_s(time.monotonic())
    end
    return os.time()
end

-- The game (data, engine) is shared between all openings
local shared = {}

function ChessCircuit:getApp()
    if shared.app then return shared.app end
    local engine = Engine.new{
        bin = self.path .. "/bin/stockfish",
        tmp = tmpDir(),
        schedule = function(seconds, fn) UIManager:scheduleIn(seconds, fn) end,
        threads = 1,
        hash = 16,
    }
    if not engine:ensureRunnable() then
        logger.warn("ChessCircuit: stockfish not found or not executable", self.path)
        return nil
    end
    local settings = LuaSettings:open(DataStorage:getSettingsDir() .. "/chesscircuit.lua")
    math.randomseed(os.time())
    shared.app = App.new{
        engine = engine,
        load = function() return settings:readSetting("data") end,
        save = function(t)
            settings:saveSetting("data", t)
            settings:flush()
        end,
        now = os.time,
        clock = monotonic,
        schedule = function(seconds, fn) UIManager:scheduleIn(seconds, fn) end,
        rnd = math.random,
    }
    return shared.app
end

function ChessCircuit:open()
    local app = self:getApp()
    if not app then
        UIManager:show(InfoMessage:new{
            text = _("The chess engine (Stockfish) could not start.\n\nCheck that the file \"bin/stockfish\" is present in the chesscircuit.koplugin folder."),
        })
        return
    end
    app:openMain()
end

return ChessCircuit
