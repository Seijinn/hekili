-- Headless checks for Hekili Observe. No game client.
package.path = package.path .. ";./src/?.lua"
local Observe = require("Hekili_Observe.Observe")
local displayed = require("Observe.Recommendation")

local SECRET = 8675309

local function readfile(path)
    local f = assert(io.open(path, "rb"))
    local text = f:read("*a")
    f:close()
    return text
end

local function walk_has(value, needle, seen)
    if value == needle then
        return true
    end
    if type(value) ~= "table" then
        return false
    end
    if seen[value] then
        return false
    end
    seen[value] = true
    local k, v
    for k, v in pairs(value) do
        if walk_has(k, needle, seen) or walk_has(v, needle, seen) then
            return true
        end
    end
    return false
end

local function harness(handlers, opts)
    opts = opts or {}
    local calls = {}
    local api = {
        issecretvalue = opts.secret,
        luaVersion = opts.luaVersion,
        projectId = opts.projectId,
        recommendation = opts.recommendation,
        fn = function(name)
            local impl = handlers[name]
            if type(impl) ~= "function" then
                return nil
            end
            return function(...)
                calls[name] = (calls[name] or 0) + 1
                return impl(...)
            end
        end,
    }
    return api, calls
end

local function plain(value)
    return value == SECRET
end

describe("Hekili Observe", function()
    it("stays disarmed and does not touch saved profiles until Start", function()
        assert.is_nil(_G.HekiliObserveDB)
        assert.is_nil(_G.HekiliDB)
        local session = Observe.New(8)
        assert.is_false(session.armed)
        local api, calls = harness({
            GetTime = function()
                return 3
            end,
        }, { secret = plain })
        Observe.NoteCast(session, api, "sent", 71)
        assert.equal(0, session.count)
        assert.equal(0, calls.GetTime or 0)
        Observe.Start(session, api, "dungeon-1")
        assert.is_true(session.armed)
        assert.equal("dungeon-1", session.label)
        assert.equal("not-inferred", session.combatLogPermission)
        Observe.Stop(session)
        assert.is_false(session.armed)
        assert.is_nil(_G.HekiliObserveDB)
        assert.is_nil(_G.HekiliDB)
    end)

    it("does not call APIs when issecretvalue is missing", function()
        local api, calls = harness({
            GetBuildInfo = function()
                return "1.60.1", "70862", "date", 16001
            end,
            GetTime = function()
                return 1
            end,
            ["C_ChatInfo.IsLoggingCombat"] = function()
                return true, false
            end,
            GetInventoryItemID = function()
                return 1234
            end,
        })
        local session = Observe.New(8)
        Observe.Start(session, api, nil)
        assert.equal("unavailable", session.anchors.buildVersion)
        assert.equal("unavailable", session.anchors.loggingCombat)
        assert.equal("unavailable", session.equipment)
        assert.equal(0, calls.GetBuildInfo or 0)
        assert.equal(0, calls.GetTime or 0)
        assert.equal(0, calls["C_ChatInfo.IsLoggingCombat"] or 0)
        assert.equal(0, calls.GetInventoryItemID or 0)
        assert.is_false(session.anchors.loggingCombat == true)
    end)

    it("keeps a cast and the displayed suggestion as two rows at one time", function()
        local api = harness({
            GetTime = function()
                return 10
            end,
        }, {
            secret = plain,
            recommendation = function()
                return { spellId = 23922, keybind = "2", actionKey = "shield_slam" }
            end,
        })
        local session = Observe.New(8)
        Observe.Start(session, api)
        Observe.NoteCast(session, api, "sent", 78)
        local rows = Observe.Rows(session)
        assert.equal(2, #rows)
        assert.equal(10, rows[1].t)
        assert.equal(10, rows[2].t)
        assert.equal("player-cast", rows[1].source)
        assert.equal("recommendation", rows[2].source)
        assert.equal(78, rows[1].spellId)
        assert.equal(23922, rows[2].spellId)
        assert.equal("2", rows[2].keybind)
        assert.equal("shield_slam", rows[2].actionKey)
        assert.is_nil(rows[1].name)
        assert.is_nil(rows[1].guid)
        assert.is_nil(rows[2].target)
    end)

    it("stores the word secret and drops the raw value", function()
        local api = harness({
            GetTime = function()
                return 4
            end,
            GetBuildInfo = function()
                return SECRET, "70862", "date", 16001
            end,
        }, {
            secret = plain,
            recommendation = function()
                return { spellId = SECRET, keybind = "1", actionKey = "heroic_strike" }
            end,
        })
        local session = Observe.New(8)
        Observe.Start(session, api)
        Observe.NoteCast(session, api, "succeeded", SECRET)
        assert.equal("secret", session.anchors.buildVersion)
        assert.equal("70862", session.anchors.buildNumber)
        local rows = Observe.Rows(session)
        assert.equal("secret", rows[1].spellId)
        assert.equal("secret", rows[2].spellId)
        assert.equal("heroic_strike", rows[2].actionKey)
        assert.is_false(walk_has(session, SECRET, {}))
    end)

    it("drops the oldest row after the cap and counts the drop", function()
        local session = Observe.New(3)
        session.armed = true
        Observe.Add(session, { n = 1 })
        Observe.Add(session, { n = 2 })
        Observe.Add(session, { n = 3 })
        Observe.Add(session, { n = 4 })
        assert.equal(1, session.dropped)
        assert.equal(3, session.count)
        local rows = Observe.Rows(session)
        assert.same({ { n = 2 }, { n = 3 }, { n = 4 } }, rows)
    end)

    it("coalesces power to integer changes and at most one write per interval", function()
        local session = Observe.New(8)
        session.armed = true
        local api = harness({}, { secret = plain })
        Observe.NotePower(session, api, 1, 10.2)
        Observe.NotePower(session, api, 1.05, 10.8)
        assert.equal(1, session.count)
        Observe.NotePower(session, api, 1.06, 11)
        assert.equal(1, session.count)
        assert.equal(11, Observe.Rows(session)[1].value)
        Observe.NotePower(session, api, 1.3, 12)
        assert.equal(2, session.count)
        assert.equal(12, Observe.Rows(session)[2].value)
    end)

    it("counts target changes without a name or guid", function()
        local api = harness({
            GetTime = function()
                return 8
            end,
        }, { secret = plain })
        local session = Observe.New(8)
        Observe.Start(session, api)
        Observe.NoteTarget(session, api)
        Observe.NoteTarget(session, api)
        local rows = Observe.Rows(session)
        assert.equal(2, rows[#rows].n)
        assert.equal("target-changed", rows[#rows].kind)
        assert.is_nil(rows[#rows].name)
        assert.is_nil(rows[#rows].guid)
        assert.is_nil(rows[#rows].unit)
    end)

    it("reads the published primary recommendation and does not refresh it", function()
        local engine = { Output = { Primary = { count = 1, recs = { { actionID = 355, keybind = "T", actionName = "taunt" } } } } }
        local got = displayed(engine, function()
            return false
        end)
        assert.equal(355, got.spellId)
        assert.equal("T", got.keybind)
        assert.equal("taunt", got.actionKey)
        local hidden = displayed(engine, nil)
        assert.equal("unavailable", hidden.spellId)
        local empty = displayed({ Output = { Primary = { count = 0, recs = {} } } }, function()
            return false
        end)
        assert.equal("unavailable", empty.spellId)
        local source = readfile("src/Hekili/Observe/Recommendation.lua")
        assert.is_nil(source:find("Update(", 1, true))
        assert.is_nil(source:find("HekiliDB", 1, true))
        assert.is_nil(source:find("ForceUpdate", 1, true))
    end)

    it("keeps private and combat-log controls out of the addon sources", function()
        local files = {
            "src/Hekili_Observe/Observe.lua",
            "src/Hekili_Observe/Boot.lua",
            "src/Hekili/Observe/Recommendation.lua",
        }
        local forbidden = {
            "UnitName",
            "UnitGUID",
            "LoggingCombat(",
            "ReloadUI",
            "OnUpdate",
            "CHAT_MSG",
            "SendAddonMessage",
            "CombatLogGetCurrentEventInfo",
            "GetCurrentEventInfo",
            "ConsoleExec",
        }
        local i, j, text, token
        for i = 1, #files do
            text = readfile(files[i])
            for j = 1, #forbidden do
                token = forbidden[j]
                assert.is_nil(text:find(token, 1, true), files[i] .. " " .. token)
            end
            assert.is_nil(text:gsub("HekiliObserveDB", ""):find("HekiliDB", 1, true), files[i])
        end
        local boot = readfile("src/Hekili_Observe/Boot.lua")
        local startAt = assert(boot:find("local function start", 1, true))
        local registerAt = assert(boot:find("RegisterEvent", 1, true))
        assert.is_true(startAt < registerAt)
        assert.is_nil(boot:find("SetScript(\"OnUpdate\"", 1, true))
        local diag = readfile("src/Hekili/Diagnostics/WarriorCapability.lua")
        assert.is_nil(diag:find("HekiliObserve", 1, true))
    end)
end)
