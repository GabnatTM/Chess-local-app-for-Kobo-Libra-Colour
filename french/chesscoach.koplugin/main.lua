--[[
  Le Circuit — jeu d'échecs pour KOReader : coach, tournois, parties libres.
  Ajoute « Le Circuit (échecs) » dans le menu Outils.
]]

local DataStorage = require("datastorage")
local Dispatcher = require("dispatcher")
local InfoMessage = require("ui/widget/infomessage")
local LuaSettings = require("luasettings")
local UIManager = require("ui/uimanager")
local WidgetContainer = require("ui/widget/container/widgetcontainer")
local logger = require("logger")
local _ = require("gettext")

-- Modules du plugin (chargés ici, pendant que le dossier du plugin est dans le chemin)
local Engine = require("cc_engine")
local App = require("cc_app")

local ok_time, time = pcall(require, "ui/time")

local ChessCoach = WidgetContainer:extend{
    name = "chesscoach",
    is_doc_only = false,
}

function ChessCoach:onDispatcherRegisterActions()
    Dispatcher:registerAction("chesscoach_open", {
        category = "none", event = "OpenChessCoach", title = _("Le Circuit (échecs)"), general = true,
    })
end

function ChessCoach:init()
    self:onDispatcherRegisterActions()
    self.ui.menu:registerToMainMenu(self)
end

function ChessCoach:addToMainMenu(menu_items)
    menu_items.chesscoach = {
        text = _("Le Circuit (échecs)"),
        sorting_hint = "tools",
        callback = function() self:open() end,
    }
end

function ChessCoach:onOpenChessCoach()
    self:open()
    return true
end

local function tmpDir()
    local f = io.open("/tmp/.chesscoach_w", "w")
    if f then
        f:close()
        os.remove("/tmp/.chesscoach_w")
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

-- Le jeu (données, moteur) est partagé entre toutes les ouvertures
local shared = {}

function ChessCoach:getApp()
    if shared.app then return shared.app end
    local engine = Engine.new{
        bin = self.path .. "/bin/stockfish",
        tmp = tmpDir(),
        schedule = function(seconds, fn) UIManager:scheduleIn(seconds, fn) end,
        threads = 1,
        hash = 16,
    }
    if not engine:ensureRunnable() then
        logger.warn("ChessCoach: stockfish introuvable ou non exécutable", self.path)
        return nil
    end
    local settings = LuaSettings:open(DataStorage:getSettingsDir() .. "/chesscoach.lua")
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

function ChessCoach:open()
    local app = self:getApp()
    if not app then
        UIManager:show(InfoMessage:new{
            text = _("Le moteur d'échecs (Stockfish) n'a pas pu démarrer.\n\nVérifiez que le fichier « bin/stockfish » est bien présent dans le dossier du plugin chesscoach.koplugin."),
        })
        return
    end
    app:openMain()
end

return ChessCoach
