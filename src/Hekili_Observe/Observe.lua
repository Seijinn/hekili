-- Hekili_Observe/Observe.lua
-- Pure session buffer. Recording stays off until Start. No frames, events, or SavedVariables here.
-- API names are strings resolved by the caller. A missing issecretvalue withholds values and does not call them.
-- Disk combat-log status is not combat-log event permission. This file never calls LoggingCombat.

local M = {}

M.CAP = 2000
M.POWER_INTERVAL = 0.1
M.SCHEMA = 1

local function packn(...)
    local n = select("#", ...)
    local packed = { n = n }
    local i
    for i = 1, n do
        packed[i] = select(i, ...)
    end
    return packed
end

function M.Gate(secret, value)
    if type(secret) ~= "function" then
        return "unavailable"
    end
    if secret(value) then
        return "secret"
    end
    if value == nil then
        return "unknown"
    end
    local kind = type(value)
    if kind == "number" or kind == "string" or kind == "boolean" then
        return value
    end
    return "unknown"
end

function M.Label(text)
    if type(text) ~= "string" then
        return false
    end
    if string.find(text, "^%s*$") then
        return false
    end
    if #text > 64 then
        text = string.sub(text, 1, 64)
    end
    return text
end

function M.New(cap)
    return {
        schema = M.SCHEMA,
        armed = false,
        cap = cap or M.CAP,
        count = 0,
        head = 1,
        dropped = 0,
        slots = {},
        targetChanges = 0,
        powerInterval = M.POWER_INTERVAL,
        combatLogPermission = "not-inferred",
        label = false,
    }
end

function M.Rows(session)
    local out = {}
    local i, idx
    if session.dropped == 0 then
        for i = 1, session.count do
            out[i] = session.slots[i]
        end
        return out
    end
    for i = 0, session.count - 1 do
        idx = (session.head + i - 1) % session.cap + 1
        out[i + 1] = session.slots[idx]
    end
    return out
end

function M.Add(session, row)
    if not session.armed then
        return false
    end
    local cap = session.cap
    if session.count < cap then
        session.count = session.count + 1
        session.slots[session.count] = row
        return true
    end
    session.slots[session.head] = row
    session.head = session.head % cap + 1
    session.dropped = session.dropped + 1
    return true
end

local function canCall(api, name)
    if type(api.issecretvalue) ~= "function" then
        return nil
    end
    local fn = api.fn(name)
    if type(fn) ~= "function" then
        return nil
    end
    return fn
end

function M.Now(api)
    local fn = canCall(api, "GetTime")
    if not fn then
        return "unavailable"
    end
    return M.Gate(api.issecretvalue, fn())
end

local function readAt(api, name, index, ...)
    local fn = canCall(api, name)
    if not fn then
        return "unavailable"
    end
    local packed = packn(fn(...))
    if index > packed.n then
        return "unknown"
    end
    return M.Gate(api.issecretvalue, packed[index])
end

function M.Anchors(api)
    local buildFn = canCall(api, "GetBuildInfo")
    local version, build, date, interface = "unavailable", "unavailable", "unavailable", "unavailable"
    if buildFn then
        local packed = packn(buildFn())
        version = M.Gate(api.issecretvalue, packed[1])
        build = M.Gate(api.issecretvalue, packed[2])
        date = M.Gate(api.issecretvalue, packed[3])
        interface = M.Gate(api.issecretvalue, packed[4])
    end
    local logFn = canCall(api, "C_ChatInfo.IsLoggingCombat")
    local logging, advanced = "unavailable", "unavailable"
    if logFn then
        local packed = packn(logFn())
        logging = M.Gate(api.issecretvalue, packed[1])
        advanced = M.Gate(api.issecretvalue, packed[2])
    end
    return {
        getTime = M.Now(api),
        serverTime = readAt(api, "GetServerTime", 1),
        buildVersion = version,
        buildNumber = build,
        buildDate = date,
        interface = interface,
        loggingCombat = logging,
        loggingAdvanced = advanced,
        combatLogRestricted = readAt(api, "C_CombatLog.IsCombatLogRestricted", 1),
        combatLogPermission = "not-inferred",
        luaVersion = api.luaVersion or "unavailable",
        projectId = api.projectId or "unavailable",
    }
end

function M.SnapshotEquipment(api)
    local fn = canCall(api, "GetInventoryItemID")
    if not fn then
        return "unavailable"
    end
    local slots = {}
    local slot
    for slot = 1, 19 do
        slots[slot] = M.Gate(api.issecretvalue, fn("player", slot))
    end
    return slots
end

function M.SnapshotBindings(api)
    local spellFn = canCall(api, "C_ActionBar.GetSpell")
    local keyFn = canCall(api, "GetBindingKey")
    local out = {}
    local i
    for i = 1, 12 do
        local spellId, key = "unavailable", "unavailable"
        if spellFn then
            spellId = M.Gate(api.issecretvalue, spellFn(i))
        end
        if keyFn then
            local packed = packn(keyFn("ACTIONBUTTON" .. i))
            key = M.Gate(api.issecretvalue, packed[1])
        end
        out[i] = { spellId = spellId, key = key }
    end
    return out
end

function M.Start(session, api, label)
    session.count = 0
    session.head = 1
    session.dropped = 0
    session.slots = {}
    session.targetChanges = 0
    session.lastPower = nil
    session.lastPowerT = nil
    session.lastPowerSlot = nil
    session.armed = true
    session.label = M.Label(label)
    session.anchors = M.Anchors(api)
    session.equipment = M.SnapshotEquipment(api)
    session.bindings = M.SnapshotBindings(api)
    session.combatLogPermission = "not-inferred"
    return session
end

function M.Stop(session)
    session.armed = false
    return session
end

function M.NoteCast(session, api, kind, spellId)
    if not session.armed then
        return
    end
    local secret = api.issecretvalue
    local t = M.Now(api)
    local shown
    if type(api.recommendation) == "function" then
        shown = api.recommendation()
    end
    local recSpell, keybind, actionKey = "unavailable", "unavailable", "unavailable"
    if type(shown) == "table" then
        recSpell = M.Gate(secret, shown.spellId)
        keybind = M.Gate(secret, shown.keybind)
        actionKey = M.Gate(secret, shown.actionKey)
    end
    M.Add(session, { source = "player-cast", kind = kind, t = t, spellId = M.Gate(secret, spellId) })
    M.Add(session, {
        source = "recommendation",
        kind = "displayed",
        t = t,
        spellId = recSpell,
        keybind = keybind,
        actionKey = actionKey,
    })
end

function M.NotePower(session, api, t, value)
    if not session.armed then
        return
    end
    local secret = api.issecretvalue
    local stored = M.Gate(secret, value)
    local time = M.Gate(secret, t)
    if type(stored) == "number" and type(session.lastPower) == "number" then
        if math.floor(stored) == math.floor(session.lastPower) then
            return
        end
    elseif stored == session.lastPower then
        return
    end
    if type(time) == "number" and type(session.lastPowerT) == "number" and (time - session.lastPowerT) < session.powerInterval then
        local prev = session.lastPowerSlot and session.slots[session.lastPowerSlot]
        if type(prev) == "table" and prev.kind == "power" then
            prev.value = stored
            prev.t = time
            session.lastPower = stored
            session.lastPowerT = time
            return
        end
    end
    M.Add(session, { source = "game", kind = "power", t = time, value = stored })
    if session.dropped == 0 then
        session.lastPowerSlot = session.count
    else
        session.lastPowerSlot = (session.head - 2) % session.cap + 1
    end
    session.lastPower = stored
    session.lastPowerT = time
end

function M.NoteForm(session, api)
    if not session.armed then
        return
    end
    local spell = "unavailable"
    local formFn = canCall(api, "GetShapeshiftForm")
    local infoFn = canCall(api, "GetShapeshiftFormInfo")
    if formFn and infoFn then
        local form = formFn()
        if api.issecretvalue(form) then
            spell = "secret"
        elseif type(form) ~= "number" or form < 1 then
            spell = "unknown"
        else
            local packed = packn(infoFn(form))
            spell = M.Gate(api.issecretvalue, packed[4])
        end
    end
    M.Add(session, { source = "game", kind = "form", t = M.Now(api), spellId = spell })
end

function M.NoteTarget(session, api)
    if not session.armed then
        return
    end
    session.targetChanges = session.targetChanges + 1
    M.Add(session, { source = "game", kind = "target-changed", t = M.Now(api), n = session.targetChanges })
end

local loadedAs, addonTable = ...
if type(addonTable) == "table" then
    addonTable.Observe = M
end

return M
