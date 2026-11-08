-- Headless checks for the opt-in Warrior capability diagnostic. No game client.
local diag = require("Diagnostics.WarriorCapability")

local SECRET = 8675309

local function readfile(path)
    local f = assert(io.open(path, "rb"))
    local text = f:read("*a")
    f:close()
    return text
end

local function slice(text, open, close)
    local at = assert(text:find(open, 1, true), open)
    local from = at + #open
    local stop = assert(text:find(close, from, true), close)
    return text:sub(from, stop - 1)
end

local function numbers(body)
    local ids = {}
    for n in body:gmatch("%d+") do
        ids[#ids + 1] = tonumber(n)
    end
    return ids
end

local function same_group(actual, expected)
    assert.equal(expected.key, actual.key)
    assert.equal(expected.kind, actual.kind)
    assert.equal(expected.source, actual.source)
    assert.same(expected.ranks, actual.ranks)
end

local function catalog_from_warrior(text)
    local lists = {}
    for name, body in text:gmatch("local%s+([A-Z][A-Z0-9_]+)%s*=%s*{([^{}]*)}") do
        lists[name] = numbers(body)
    end
    local tactical = tonumber(text:match("local%s+TACTICAL_MASTERY%s*=%s*(%d+)"))
    local abilities = slice(text, "spec:RegisterAbilities({", "\n})")
    local marks = {}
    local pos = 1
    while true do
        local startAt, stopAt, key = abilities:find("\n    ([%w_]+) = {", pos)
        if not startAt then
            break
        end
        marks[#marks + 1] = { key = key, at = startAt }
        pos = stopAt
    end
    local expected = {
        { key = "tactical_mastery", kind = "ability", source = "TACTICAL_MASTERY", ranks = { tactical } },
    }
    local i
    for i = 1, #marks do
        local stop = marks[i + 1] and marks[i + 1].at or (#abilities + 1)
        local body = abilities:sub(marks[i].at, stop - 1)
        local arg = assert(body:match("known%s*=%s*knows%(([^)]+)%)"), marks[i].key)
        local source, ranks
        if arg:sub(1, 1) == "{" then
            source = "literal"
            ranks = numbers(arg)
        else
            source = arg
            ranks = lists[arg]
        end
        expected[#expected + 1] = { key = marks[i].key, kind = "ability", source = source, ranks = ranks }
    end
    local talents = slice(text, "spec:RegisterTalents({", "\n})")
    for key, _, spell in talents:gmatch("([%w_]+)%s*=%s*{%s*(%d+)%s*,%s*(%d+)%s*,%s*(%d+)%s*}") do
        expected[#expected + 1] = {
            key = key,
            kind = "talent",
            source = "RegisterTalents",
            ranks = { tonumber(spell) },
        }
    end
    return expected
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
        camelotConstant = opts.camelot,
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

local function plain_secret(value)
    return value == SECRET
end

describe("Warrior capability diagnostic", function()
    it("matches the spell and talent ids Warrior.lua registers", function()
        local expected = catalog_from_warrior(readfile("src/Hekili_Warrior/Warrior.lua"))
        assert.equal(#expected, #diag.SPELLS)
        local i
        for i = 1, #expected do
            same_group(diag.SPELLS[i], expected[i])
            local r
            for r = 1, #diag.SPELLS[i].ranks do
                assert.is_true(diag.SPELLS[i].ranks[r] >= 71)
            end
        end
    end)

    it("does not store a report merely by being loaded", function()
        assert.is_nil(_G.HekiliDiagnosticDB)
        local wrote = 0
        diag.Diagnose({ fn = function() return nil end })
        assert.equal(0, wrote)
        assert.is_nil(_G.HekiliDiagnosticDB)
    end)

    it("withholds API returns when issecretvalue is absent and does not call them", function()
        local api, calls = harness({
            GetBuildInfo = function()
                return "1.60.1", "70862", "date", 16001
            end,
            ["C_Spell.IsSpellKnown"] = function()
                return true
            end,
            ["C_Spell.GetSpellLevelLearned"] = function()
                return 10
            end,
        })
        local report = diag.Diagnose(api)
        assert.equal("withheld", report.secrecy)
        assert.equal("unavailable", report.build.version)
        assert.equal("unavailable", report.build.interface)
        assert.equal("unavailable", report.classFile)
        assert.equal(0, calls.GetBuildInfo or 0)
        assert.equal(0, calls["C_Spell.GetSpellLevelLearned"] or 0)
        assert.equal("unavailable", report.spells[1].levelLearned)
        assert.equal("unavailable", report.spells[1].isKnown)
        assert.is_false(report.spells[1].isKnown == false)
        assert.is_false(report.spells[1].levelLearned == 0)
        assert.is_true(report.presence["C_Spell.GetSpellLevelLearned"])
        assert.is_false(report.presence["C_Spell.IsSpellUsable"])
        assert.equal("omitted", report.combatLog)
        assert.is_false(report.recordedPlay)
        assert.is_false(report.recommendationsChanged)
    end)

    it("keeps false, zero, nil, and missing functions distinct", function()
        local rows = 0
        local i, g
        for i = 1, #diag.SPELLS do
            rows = rows + #diag.SPELLS[i].ranks
        end
        local api, calls = harness({
            GetBuildInfo = function()
                return "1.60.1", "70862", "2026", 16001, "do-not-store-localized", "do-not-store-blob"
            end,
            GetTime = function()
                return 12.5
            end,
            UnitClassBase = function(unit)
                assert.equal("player", unit)
                return "WARRIOR", 1
            end,
            ["C_AddOns.GetAddOnMetadata"] = function(name, field)
                assert.equal("Hekili", name)
                assert.equal("Version", field)
                return "v0.6.1"
            end,
            ["C_CVar.GetCVar"] = function(name)
                assert.equal("loadDeprecationFallbacks", name)
                return nil
            end,
            ["C_Secrets.HasSecretRestrictions"] = function()
                return true
            end,
            ["C_Secrets.ShouldAurasBeSecret"] = function()
                return false
            end,
            ["C_Secrets.ShouldCooldownsBeSecret"] = function()
                return false
            end,
            ["C_Secrets.ShouldUnitPowerBeSecret"] = function(unit, power)
                assert.equal("player", unit)
                assert.is_nil(power)
                return true
            end,
            ["C_AddOns.GetScriptsDisallowedForBeta"] = function()
                return false
            end,
            ["C_RestrictedActions.InCombatLockdown"] = function()
                return false
            end,
            ["C_Spell.GetSpellLevelLearned"] = function(id)
                if id == 71 then
                    return 0
                end
                if id == 355 then
                    return nil
                end
                return 10
            end,
            ["C_SpellBook.IsSpellKnown"] = function(id)
                return id == 71
            end,
            ["C_SpellBook.IsSpellInSpellBook"] = function(id)
                return id == 2457
            end,
            ["C_Spell.IsSpellUsable"] = function(id)
                if id == 71 then
                    return true, false
                end
                return false, true
            end,
        }, { secret = plain_secret, luaVersion = "Lua 5.1", projectId = 18, camelot = 18 })
        local report = diag.Diagnose(api)
        assert.equal("checked", report.secrecy)
        assert.equal("1.60.1", report.build.version)
        assert.equal("70862", report.build.build)
        assert.equal(16001, report.build.interface)
        assert.equal("v0.6.1", report.build.addonVersion)
        assert.equal(12.5, report.capturedAt)
        assert.equal("Lua 5.1", report.lua.version)
        assert.equal(18, report.project.id)
        assert.equal("unknown", report.cvar.loadDeprecationFallbacks)
        assert.is_true(report.restrictions.hasSecretRestrictions)
        assert.is_false(report.restrictions.aurasSecret)
        assert.is_true(report.restrictions.unitPowerSecret)
        assert.is_false(report.restrictions.inCombatLockdown)
        assert.equal("WARRIOR", report.classFile)
        assert.equal(#diag.LIMITATIONS, #report.limitations)
        assert.is_false(walk_has(report, "do-not-store-localized", {}))
        assert.is_false(walk_has(report, "do-not-store-blob", {}))
        assert.equal(rows, calls["C_Spell.IsSpellUsable"])
        assert.equal(rows, calls["C_SpellBook.IsSpellKnown"])
        assert.equal(rows, calls["C_Spell.GetSpellLevelLearned"])
        local byId = {}
        for i = 1, #report.spells do
            byId[report.spells[i].id .. ":" .. report.spells[i].kind] = report.spells[i]
        end
        assert.equal(0, byId["71:ability"].levelLearned)
        assert.is_true(byId["71:ability"].isKnown)
        assert.is_false(byId["71:ability"].isInSpellBook)
        assert.is_true(byId["71:ability"].isUsable)
        assert.is_false(byId["71:ability"].insufficientPower)
        assert.equal("unknown", byId["355:ability"].levelLearned)
        assert.is_false(byId["355:ability"].isKnown)
        assert.is_true(byId["2457:ability"].isInSpellBook)
        assert.is_false(byId["2457:ability"].isKnown)
        assert.equal("unavailable", (function()
            local missing = harness({
                ["C_SpellBook.IsSpellKnown"] = function()
                    return false
                end,
            }, { secret = plain_secret })
            local other = diag.Diagnose(missing)
            return other.spells[1].levelLearned
        end)())
    end)

    it("stores the word secret and drops the raw secret value", function()
        local built = harness({
            GetBuildInfo = function()
                return SECRET, "70862", "date", 16001
            end,
            UnitClassBase = function()
                return SECRET
            end,
            ["C_Spell.GetSpellLevelLearned"] = function()
                return SECRET
            end,
            ["C_SpellBook.IsSpellKnown"] = function()
                return SECRET
            end,
            ["C_SpellBook.IsSpellInSpellBook"] = function()
                return false
            end,
            ["C_Spell.IsSpellUsable"] = function()
                return SECRET, false
            end,
        }, { secret = plain_secret })
        local report = diag.Diagnose(built)
        assert.equal("secret", report.build.version)
        assert.equal("70862", report.build.build)
        assert.equal("secret", report.classFile)
        assert.equal("secret", report.spells[1].levelLearned)
        assert.equal("secret", report.spells[1].isKnown)
        assert.equal("secret", report.spells[1].isUsable)
        assert.is_false(report.spells[1].insufficientPower)
        assert.is_false(walk_has(report, SECRET, {}))
    end)

    it("notes a non-warrior class without turning known into a level gate", function()
        local api = harness({
            UnitClassBase = function()
                return "MAGE"
            end,
            ["C_SpellBook.IsSpellKnown"] = function()
                return false
            end,
        }, { secret = plain_secret })
        local report = diag.Diagnose(api)
        assert.equal("MAGE", report.classFile)
        assert.is_false(report.spells[1].isKnown)
        assert.equal("unavailable", report.spells[1].levelLearned)
        local found = false
        local i
        for i = 1, #report.limitations do
            if report.limitations[i]:find("did not return WARRIOR", 1, true) then
                found = true
            end
        end
        assert.is_true(found)
    end)

    it("writes only through the explicit Run callback", function()
        local stored
        local api = harness({}, { secret = plain_secret, luaVersion = "Lua 5.1", projectId = 18 })
        local report = diag.Run(api, function(value)
            stored = value
        end)
        assert.equal(report, stored)
        assert.equal("warrior-capability-diagnostic", stored.purpose)
        assert.is_nil(_G.HekiliDiagnosticDB)
    end)

    it("does not read project or Lua globals when issecretvalue is missing", function()
        local env = setmetatable({ issecretvalue = nil }, {
            __index = function(_, key)
                if key == "_VERSION" or key == "WOW_PROJECT_ID" or key == "WOW_PROJECT_CAMELOT" then
                    error("touched " .. key)
                end
                return nil
            end,
        })
        local api = diag.ClientApi(env)
        assert.equal("unavailable", api.luaVersion)
        assert.equal("unavailable", api.projectId)
        assert.equal("unavailable", api.camelotConstant)
        assert.is_nil(api.issecretvalue)
    end)

    it("gates ClientApi globals and keeps a secret project id out of the report", function()
        local env = {
            issecretvalue = plain_secret,
            _VERSION = "Lua 5.1",
            WOW_PROJECT_ID = SECRET,
            WOW_PROJECT_CAMELOT = 18,
        }
        local api = diag.ClientApi(env)
        assert.equal("Lua 5.1", api.luaVersion)
        assert.equal("secret", api.projectId)
        assert.equal(18, api.camelotConstant)
        local report = diag.Diagnose(api)
        assert.equal("secret", report.project.id)
        assert.is_false(walk_has(report, SECRET, {}))
    end)

    it("keeps the slash command off the recommendation refresh path", function()
        local text = readfile("src/Hekili/Options/ChatCommands.lua")
        local diagAt = assert(text:find('command == "diag"', 1, true))
        local refreshAt = assert(text:find("self:UpdateDisplayVisibility()", diagAt, true))
        assert.is_true(diagAt < refreshAt)
        local startFn = assert(text:find("function Hekili:RunWarriorCapabilityDiagnostic()", 1, true))
        local finishFn = assert(text:find("\nend\n", startFn, true))
        local body = text:sub(startFn, finishFn)
        assert.is_truthy(body:find("HekiliDiagnosticDB", 1, true))
        assert.is_nil(body:find("ForceUpdate", 1, true))
        assert.is_nil(body:find("MakeSnapshot", 1, true))
        assert.is_nil(body:gsub("HekiliDiagnosticDB", ""):find("HekiliDB", 1, true))
        local module = readfile("src/Hekili/Diagnostics/WarriorCapability.lua")
        assert.is_nil(module:find("pcall", 1, true))
        assert.is_nil(module:find("CastSpell", 1, true))
        assert.is_nil(module:find("UseAction", 1, true))
        assert.is_nil(module:find("RunMacro", 1, true))
        assert.is_nil(module:find("RegisterEvent", 1, true))
        assert.is_nil(module:find("CreateFrame", 1, true))
        local toc = readfile("src/Hekili/Hekili.toc")
        assert.is_truthy(toc:find("HekiliDiagnosticDB", 1, true))
        assert.is_truthy(toc:find("HekiliDB", 1, true))
    end)
end)
