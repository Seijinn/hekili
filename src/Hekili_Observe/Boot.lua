-- Hekili_Observe/Boot.lua
-- In-game arm and stop. Events are registered only from start. There is no per-frame script.
-- LoggingCombat, reload, and combat-log event getters are not called.

local _, ns = ...
local Observe = ns.Observe

local EVENTS = {
    "UNIT_SPELLCAST_SENT",
    "UNIT_SPELLCAST_SUCCEEDED",
    "UNIT_SPELLCAST_FAILED",
    "UNIT_SPELLCAST_INTERRUPTED",
    "UNIT_POWER_UPDATE",
    "UPDATE_SHAPESHIFT_FORM",
    "PLAYER_TARGET_CHANGED",
    "PLAYER_EQUIPMENT_CHANGED",
    "UPDATE_BINDINGS",
}

local SPELL_INDEX = {
    UNIT_SPELLCAST_SENT = 4,
    UNIT_SPELLCAST_SUCCEEDED = 3,
    UNIT_SPELLCAST_FAILED = 3,
    UNIT_SPELLCAST_INTERRUPTED = 3,
}

local CAST_KIND = {
    UNIT_SPELLCAST_SENT = "sent",
    UNIT_SPELLCAST_SUCCEEDED = "succeeded",
    UNIT_SPELLCAST_FAILED = "failed",
    UNIT_SPELLCAST_INTERRUPTED = "interrupted",
}

local frame
local session

local function env()
    return _G
end

local function resolve(name)
    local dot = string.find(name, ".", 1, true)
    local box = env()
    if not dot then
        return box[name]
    end
    local head = string.sub(name, 1, dot - 1)
    local tail = string.sub(name, dot + 1)
    local nsTable = box[head]
    if type(nsTable) ~= "table" then
        return nil
    end
    return nsTable[tail]
end

local function api()
    local secret = resolve("issecretvalue")
    local luaVersion, projectId = "unavailable", "unavailable"
    if type(secret) == "function" then
        if not secret(env()._VERSION) and type(env()._VERSION) == "string" then
            luaVersion = env()._VERSION
        elseif secret(env()._VERSION) then
            luaVersion = "secret"
        end
        local project = env().WOW_PROJECT_ID
        if secret(project) then
            projectId = "secret"
        elseif type(project) == "number" then
            projectId = project
        end
    end
    return {
        fn = resolve,
        issecretvalue = type(secret) == "function" and secret or nil,
        luaVersion = luaVersion,
        projectId = projectId,
        recommendation = function()
            local addon = env().Hekili
            if type(addon) ~= "table" or type(addon.GetDisplayedRecommendation) ~= "function" then
                return nil
            end
            return addon:GetDisplayedRecommendation()
        end,
    }
end

local function isPlayer(hook, unit)
    if type(hook.issecretvalue) ~= "function" or hook.issecretvalue(unit) then
        return false
    end
    return unit == "player"
end

local function say(text)
    local chat = resolve("DEFAULT_CHAT_FRAME")
    if type(chat) == "table" and type(chat.AddMessage) == "function" then
        chat:AddMessage(text)
    end
end

local function onEvent(_, event, ...)
    if not session or not session.armed then
        return
    end
    local hook = api()
    local kind = CAST_KIND[event]
    if kind then
        local unit = select(1, ...)
        if isPlayer(hook, unit) then
            Observe.NoteCast(session, hook, kind, select(SPELL_INDEX[event], ...))
        end
        return
    end
    if event == "UNIT_POWER_UPDATE" then
        local unit = select(1, ...)
        if isPlayer(hook, unit) then
            local power = resolve("UnitPower")
            if type(power) == "function" and type(hook.issecretvalue) == "function" then
                Observe.NotePower(session, hook, Observe.Now(hook), power("player"))
            end
        end
        return
    end
    if event == "UPDATE_SHAPESHIFT_FORM" then
        Observe.NoteForm(session, hook)
        return
    end
    if event == "PLAYER_TARGET_CHANGED" then
        Observe.NoteTarget(session, hook)
        return
    end
    if event == "PLAYER_EQUIPMENT_CHANGED" then
        session.equipment = Observe.SnapshotEquipment(hook)
        return
    end
    if event == "UPDATE_BINDINGS" then
        session.bindings = Observe.SnapshotBindings(hook)
    end
end

local function ensureFrame()
    if frame then
        return frame
    end
    local create = resolve("CreateFrame")
    if type(create) ~= "function" then
        return nil
    end
    frame = create("Frame")
    frame:SetScript("OnEvent", onEvent)
    return frame
end

local function start(label)
    local hook = api()
    session = Observe.New()
    Observe.Start(session, hook, label)
    if type(env().HekiliObserveDB) ~= "table" then
        env().HekiliObserveDB = { schema = Observe.SCHEMA }
    end
    env().HekiliObserveDB.schema = Observe.SCHEMA
    env().HekiliObserveDB.armed = true
    env().HekiliObserveDB.session = session
    local box = ensureFrame()
    if box then
        local i
        for i = 1, #EVENTS do
            box:RegisterEvent(EVENTS[i])
        end
    end
    say("Hekili Observe recording. /reload or log out to write SavedVariables/Hekili_Observe.lua. The combat-log file was not toggled. Recommendations were not changed.")
end

local function stop()
    if session then
        Observe.Stop(session)
    end
    if frame then
        frame:UnregisterAllEvents()
    end
    if type(env().HekiliObserveDB) == "table" then
        env().HekiliObserveDB.armed = false
    end
    say("Hekili Observe stopped. Rows stay in memory until /reload or logout.")
end

if type(env().HekiliObserveDB) == "table" then
    env().HekiliObserveDB.armed = false
end

_G.SLASH_HEKOBSERVE1 = "/hekobs"
local commands = env().SlashCmdList
if type(commands) ~= "table" then
    commands = {}
    env().SlashCmdList = commands
end
commands.HEKOBSERVE = function(msg)
    msg = msg or ""
    local cmd, rest = string.match(msg, "^(%S*)%s*(.*)$")
    cmd = string.lower(cmd or "")
    if cmd == "start" then
        start(rest)
    elseif cmd == "stop" then
        stop()
    else
        say("Hekili Observe: /hekobs start [label] or /hekobs stop. Recording stays off until start.")
    end
end
