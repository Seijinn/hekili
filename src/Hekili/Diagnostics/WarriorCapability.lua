-- Diagnostics/WarriorCapability.lua
-- Opt-in, one-shot read of build and Warrior register facts. Loaded by Hekili.toc and also
-- require()'d from tests. It does not register events, create frames, cast, or write
-- SavedVariables. Hekili:RunWarriorCapabilityDiagnostic is the only caller that stores a report.
-- Game functions are resolved from the env table passed in, not from ns.Facade, so a missing
-- function stays "unavailable" instead of a modelled answer.
-- Build scope for the names below: reckhou/WoWBlzCode 7245053a, Forever dump 1.60.1.70658
-- (2026-10-28). That dump is older than the reported Wow.exe file version 1.60.1.70862.
-- Parity is not assumed. Spell rows are the ids Warrior.lua registers, not a vanilla rank table.

local loadedAs, addonTable = ...
local ns = type(addonTable) == "table" and addonTable or nil

local M = {}

M.SCHEMA = 1

-- Names consulted only when issecretvalue exists. Strings, so this file does not bind the globals.
M.PROBES = {
    "GetBuildInfo",
    "GetTime",
    "UnitClassBase",
    "C_AddOns.GetAddOnMetadata",
    "C_AddOns.GetScriptsDisallowedForBeta",
    "C_CVar.GetCVar",
    "C_RestrictedActions.InCombatLockdown",
    "C_Secrets.HasSecretRestrictions",
    "C_Secrets.ShouldAurasBeSecret",
    "C_Secrets.ShouldCooldownsBeSecret",
    "C_Secrets.ShouldUnitPowerBeSecret",
    "C_Spell.GetSpellLevelLearned",
    "C_Spell.IsSpellUsable",
    "C_SpellBook.IsSpellKnown",
    "C_SpellBook.IsSpellInSpellBook",
    "issecretvalue",
}

M.LIMITATIONS = {
    "This capture is one character at one moment. It does not establish trainer levels, quest rewards, or racial spells for anyone else.",
    "C_Spell.GetSpellLevelLearned can return a different number while the player is Level Linked. A number here is that return, not proof of a trainer purchase.",
    "C_SpellBook.IsSpellKnown can be true for a temporary grant that is not in the spellbook. C_SpellBook.IsSpellInSpellBook can be true for an override that is not known. The two fields are not collapsed. Calls pass the spell id only and leave the documented defaults (spell bank Player, includeOverrides true).",
    "isUsable and insufficientPower are C_Spell.IsSpellUsable at this moment (stance, rage, cooldown, target, equipment). They are not 'available at this level' and not 'learned'.",
    "Talent rows are the one definition spell Warrior.lua RegisterTalents stores. That register does not list a spell id per talent rank.",
    "Quest rewards and racials are not in the Warrior register, so they are not probed. docs/research/2026-10-16-forever-protection-research.md names Devastate 403196 and Commanding Shout 403215 as not registered; they are not probed.",
    "Values are copied only after issecretvalue returns false. If that function is missing, API returns are withheld as unavailable and the functions are not called. A secret return is stored as the word secret, never as the raw value.",
    "Combat log is omitted. The 1.60.1.70658 dump marks COMBAT_LOG_EVENT HasRestrictions, and C_CombatLogSecure.GetCurrentEventInfo is Environment=SecureOnly. This diagnostic does not call those.",
    "No recommendation was produced and no play was recorded. Hekili leveling advice, if added later, is coaching. It is not a record of the player's actual actions, including mistakes.",
    "Recommendations, toggles, and HekiliDB were not modified. Nothing was cast, moved, or sent on the network.",
}

M.SPELLS = {
    { key = "tactical_mastery", kind = "ability", source = "TACTICAL_MASTERY", ranks = { 1310185 } },
    { key = "battle_shout", kind = "ability", source = "BATTLE_SHOUT", ranks = { 6673, 5242, 6192, 11549, 11550, 11551, 25289 } },
    { key = "battle_stance", kind = "ability", source = "literal", ranks = { 2457 } },
    { key = "berserker_rage", kind = "ability", source = "literal", ranks = { 18499 } },
    { key = "berserker_stance", kind = "ability", source = "literal", ranks = { 2458 } },
    { key = "bloodrage", kind = "ability", source = "literal", ranks = { 2687 } },
    { key = "bloodthirst", kind = "ability", source = "BLOODTHIRST", ranks = { 23881, 23892, 23893, 23894 } },
    { key = "challenging_shout", kind = "ability", source = "literal", ranks = { 1161 } },
    { key = "charge", kind = "ability", source = "CHARGE", ranks = { 100, 6178, 11578 } },
    { key = "cleave", kind = "ability", source = "CLEAVE", ranks = { 845, 7369, 11608, 11609, 20569 } },
    { key = "concussion_blow", kind = "ability", source = "literal", ranks = { 12809 } },
    { key = "death_wish", kind = "ability", source = "literal", ranks = { 12328 } },
    { key = "defensive_stance", kind = "ability", source = "literal", ranks = { 71 } },
    { key = "demoralizing_shout", kind = "ability", source = "DEMORALIZING_SHOUT", ranks = { 1160, 6190, 11554, 11555, 11556 } },
    { key = "disarm", kind = "ability", source = "literal", ranks = { 676 } },
    { key = "execute", kind = "ability", source = "EXECUTE", ranks = { 5308, 20658, 20660, 20661, 20662 } },
    { key = "hamstring", kind = "ability", source = "HAMSTRING", ranks = { 1715, 7372, 7373 } },
    { key = "heroic_strike", kind = "ability", source = "HEROIC_STRIKE", ranks = { 78, 284, 285, 1608, 11564, 11565, 11566, 11567, 25286 } },
    { key = "intercept", kind = "ability", source = "INTERCEPT", ranks = { 20252, 20616, 20617 } },
    { key = "intimidating_shout", kind = "ability", source = "literal", ranks = { 5246 } },
    { key = "last_stand", kind = "ability", source = "literal", ranks = { 12975 } },
    { key = "mocking_blow", kind = "ability", source = "MOCKING_BLOW", ranks = { 694, 7400, 7402, 20559, 20560 } },
    { key = "mortal_strike", kind = "ability", source = "MORTAL_STRIKE", ranks = { 12294, 21551, 21552, 21553 } },
    { key = "overpower", kind = "ability", source = "OVERPOWER", ranks = { 7384, 7887, 11584, 11585 } },
    { key = "piercing_howl", kind = "ability", source = "literal", ranks = { 12323 } },
    { key = "pummel", kind = "ability", source = "PUMMEL", ranks = { 6552, 6554 } },
    { key = "recklessness", kind = "ability", source = "literal", ranks = { 1719 } },
    { key = "rend", kind = "ability", source = "REND", ranks = { 772, 6546, 6547, 6548, 11572, 11573, 11574 } },
    { key = "retaliation", kind = "ability", source = "literal", ranks = { 20230 } },
    { key = "revenge", kind = "ability", source = "REVENGE", ranks = { 6572, 6574, 7379, 11600, 11601, 25288 } },
    { key = "shield_bash", kind = "ability", source = "SHIELD_BASH", ranks = { 72, 1671, 1672 } },
    { key = "shield_block", kind = "ability", source = "literal", ranks = { 2565 } },
    { key = "shield_slam", kind = "ability", source = "SHIELD_SLAM", ranks = { 23922, 23923, 23924, 23925 } },
    { key = "shield_wall", kind = "ability", source = "literal", ranks = { 871 } },
    { key = "slam", kind = "ability", source = "SLAM", ranks = { 1240193, 1464, 8820, 11604, 11605, 1310196, 1310197, 1310198, 1310199, 1310200 } },
    { key = "spearing_strike", kind = "ability", source = "literal", ranks = { 1310222 } },
    { key = "sunder_armor", kind = "ability", source = "SUNDER_ARMOR", ranks = { 7386, 7405, 8380, 11596, 11597 } },
    { key = "sweeping_strikes", kind = "ability", source = "literal", ranks = { 12292 } },
    { key = "taunt", kind = "ability", source = "literal", ranks = { 355 } },
    { key = "thunder_clap", kind = "ability", source = "THUNDER_CLAP", ranks = { 6343, 8198, 8204, 8205, 11580, 11581 } },
    { key = "victory_rush", kind = "ability", source = "VICTORY_RUSH", ranks = { 402927 } },
    { key = "whirlwind", kind = "ability", source = "WHIRLWIND", ranks = { 1680 } },
    { key = "improved_heroic_strike", kind = "talent", source = "RegisterTalents", ranks = { 12282 } },
    { key = "deflection", kind = "talent", source = "RegisterTalents", ranks = { 16462 } },
    { key = "improved_rend", kind = "talent", source = "RegisterTalents", ranks = { 12286 } },
    { key = "improved_charge", kind = "talent", source = "RegisterTalents", ranks = { 12285 } },
    { key = "improved_tactical_mastery", kind = "talent", source = "RegisterTalents", ranks = { 12295 } },
    { key = "improved_overpower", kind = "talent", source = "RegisterTalents", ranks = { 12290 } },
    { key = "anger_management", kind = "talent", source = "RegisterTalents", ranks = { 12296 } },
    { key = "deep_wounds", kind = "talent", source = "RegisterTalents", ranks = { 12834 } },
    { key = "two_handed_weapon_specialization", kind = "talent", source = "RegisterTalents", ranks = { 12163 } },
    { key = "impale", kind = "talent", source = "RegisterTalents", ranks = { 16493 } },
    { key = "sweeping_strikes", kind = "talent", source = "RegisterTalents", ranks = { 12292 } },
    { key = "improved_hamstring", kind = "talent", source = "RegisterTalents", ranks = { 12289 } },
    { key = "mortal_strike", kind = "talent", source = "RegisterTalents", ranks = { 12294 } },
    { key = "improved_slam", kind = "talent", source = "RegisterTalents", ranks = { 12862 } },
    { key = "weaponmaster", kind = "talent", source = "RegisterTalents", ranks = { 1290261 } },
    { key = "spearing_strike", kind = "talent", source = "RegisterTalents", ranks = { 1310222 } },
    { key = "bloodthrill", kind = "talent", source = "RegisterTalents", ranks = { 1289682 } },
    { key = "booming_voice", kind = "talent", source = "RegisterTalents", ranks = { 12321 } },
    { key = "cruelty", kind = "talent", source = "RegisterTalents", ranks = { 12320 } },
    { key = "unbridled_wrath", kind = "talent", source = "RegisterTalents", ranks = { 12322 } },
    { key = "piercing_howl", kind = "talent", source = "RegisterTalents", ranks = { 12323 } },
    { key = "blood_craze", kind = "talent", source = "RegisterTalents", ranks = { 16487 } },
    { key = "dual_wield_specialization", kind = "talent", source = "RegisterTalents", ranks = { 23584 } },
    { key = "improved_execute", kind = "talent", source = "RegisterTalents", ranks = { 20502 } },
    { key = "enrage", kind = "talent", source = "RegisterTalents", ranks = { 12317 } },
    { key = "death_wish", kind = "talent", source = "RegisterTalents", ranks = { 12328 } },
    { key = "improved_intercept", kind = "talent", source = "RegisterTalents", ranks = { 20504 } },
    { key = "improved_berserker_rage", kind = "talent", source = "RegisterTalents", ranks = { 20500 } },
    { key = "flurry", kind = "talent", source = "RegisterTalents", ranks = { 12319 } },
    { key = "bloodthirst", kind = "talent", source = "RegisterTalents", ranks = { 23881 } },
    { key = "furious_precision", kind = "talent", source = "RegisterTalents", ranks = { 1323963 } },
    { key = "raging_blows", kind = "talent", source = "RegisterTalents", ranks = { 1310315 } },
    { key = "lingering_rage", kind = "talent", source = "RegisterTalents", ranks = { 1323964 } },
    { key = "gore_drinker", kind = "talent", source = "RegisterTalents", ranks = { 1323967 } },
    { key = "shield_specialization", kind = "talent", source = "RegisterTalents", ranks = { 12298 } },
    { key = "anticipation", kind = "talent", source = "RegisterTalents", ranks = { 12297 } },
    { key = "improved_bloodrage", kind = "talent", source = "RegisterTalents", ranks = { 12301 } },
    { key = "improved_thunder_clap", kind = "talent", source = "RegisterTalents", ranks = { 12287 } },
    { key = "iron_will", kind = "talent", source = "RegisterTalents", ranks = { 12962 } },
    { key = "last_stand", kind = "talent", source = "RegisterTalents", ranks = { 12975 } },
    { key = "improved_revenge", kind = "talent", source = "RegisterTalents", ranks = { 12797 } },
    { key = "defiance", kind = "talent", source = "RegisterTalents", ranks = { 12792 } },
    { key = "improved_sunder_armor", kind = "talent", source = "RegisterTalents", ranks = { 12308 } },
    { key = "improved_disarm", kind = "talent", source = "RegisterTalents", ranks = { 12313 } },
    { key = "improved_shield_wall", kind = "talent", source = "RegisterTalents", ranks = { 12312 } },
    { key = "concussion_blow", kind = "talent", source = "RegisterTalents", ranks = { 12809 } },
    { key = "improved_shield_bash", kind = "talent", source = "RegisterTalents", ranks = { 12311 } },
    { key = "one_handed_weapon_specialization", kind = "talent", source = "RegisterTalents", ranks = { 16538 } },
    { key = "shield_slam", kind = "talent", source = "RegisterTalents", ranks = { 23922 } },
    { key = "focused_rage", kind = "talent", source = "RegisterTalents", ranks = { 29787 } },
    { key = "vanguard", kind = "talent", source = "RegisterTalents", ranks = { 1310317 } },
    { key = "master_of_defense", kind = "talent", source = "RegisterTalents", ranks = { 1310316 } },
}

local function lookup(env, name)
    local dot = string.find(name, ".", 1, true)
    if not dot then
        return env[name]
    end
    local head = string.sub(name, 1, dot - 1)
    local tail = string.sub(name, dot + 1)
    local box = env[head]
    if type(box) ~= "table" then
        return nil
    end
    return box[tail]
end

local function copyList(src)
    local out = {}
    local i
    for i = 1, #src do
        out[i] = src[i]
    end
    return out
end

local function packn(...)
    local n = select("#", ...)
    local packed = { n = n }
    local i
    for i = 1, n do
        packed[i] = select(i, ...)
    end
    return packed
end

local function invoke(api, name, ...)
    local fn = api.fn(name)
    if type(fn) ~= "function" then
        return nil
    end
    return packn(fn(...))
end

local function gate(api, packed, index)
    if not packed then
        return "unavailable"
    end
    if index > packed.n then
        return "unknown"
    end
    local value = packed[index]
    if type(api.issecretvalue) ~= "function" then
        return "unavailable"
    end
    if api.issecretvalue(value) then
        return "secret"
    end
    if value == nil then
        return "unknown"
    end
    local kind = type(value)
    if kind == "number" or kind == "boolean" or kind == "string" then
        return value
    end
    return "unknown"
end

local function presence(api)
    local out = {}
    local i, name
    for i = 1, #M.PROBES do
        name = M.PROBES[i]
        out[name] = type(api.fn(name)) == "function"
    end
    return out
end

local function spellRows(api, canRead)
    local rows = {}
    local g, r, group, id, levelPacked, knownPacked, bookPacked, usablePacked
    for g = 1, #M.SPELLS do
        group = M.SPELLS[g]
        for r = 1, #group.ranks do
            id = group.ranks[r]
            if canRead then
                levelPacked = invoke(api, "C_Spell.GetSpellLevelLearned", id)
                knownPacked = invoke(api, "C_SpellBook.IsSpellKnown", id)
                bookPacked = invoke(api, "C_SpellBook.IsSpellInSpellBook", id)
                usablePacked = invoke(api, "C_Spell.IsSpellUsable", id)
            end
            rows[#rows + 1] = {
                key = group.key,
                kind = group.kind,
                rank = r,
                id = id,
                source = group.source,
                levelLearned = gate(api, levelPacked, 1),
                isKnown = gate(api, knownPacked, 1),
                isInSpellBook = gate(api, bookPacked, 1),
                isUsable = gate(api, usablePacked, 1),
                insufficientPower = gate(api, usablePacked, 2),
            }
        end
    end
    return rows
end

local STATUS_WORD = { unavailable = true, unknown = true, secret = true }

local function classNote(filename)
    if filename == "WARRIOR" then
        return nil
    end
    if STATUS_WORD[filename] or type(filename) ~= "string" then
        return "UnitClassBase was not a plain class file, so this capture cannot confirm the character is a warrior."
    end
    return "UnitClassBase did not return WARRIOR. Spell rows are still the warrior register on this character."
end

function M.Diagnose(api)
    local canRead = type(api.issecretvalue) == "function"
    local limitations = copyList(M.LIMITATIONS)
    local classFilename = "unavailable"
    local buildPacked, classPacked, timePacked, versionPacked, cvarPacked
    local restrictionsPacked = {}
    if canRead then
        buildPacked = invoke(api, "GetBuildInfo")
        classPacked = invoke(api, "UnitClassBase", "player")
        timePacked = invoke(api, "GetTime")
        versionPacked = invoke(api, "C_AddOns.GetAddOnMetadata", "Hekili", "Version")
        cvarPacked = invoke(api, "C_CVar.GetCVar", "loadDeprecationFallbacks")
        restrictionsPacked.hasSecretRestrictions = invoke(api, "C_Secrets.HasSecretRestrictions")
        restrictionsPacked.aurasSecret = invoke(api, "C_Secrets.ShouldAurasBeSecret")
        restrictionsPacked.cooldownsSecret = invoke(api, "C_Secrets.ShouldCooldownsBeSecret")
        restrictionsPacked.unitPowerSecret = invoke(api, "C_Secrets.ShouldUnitPowerBeSecret", "player")
        restrictionsPacked.scriptsDisallowedForBeta = invoke(api, "C_AddOns.GetScriptsDisallowedForBeta")
        restrictionsPacked.inCombatLockdown = invoke(api, "C_RestrictedActions.InCombatLockdown")
        classFilename = gate(api, classPacked, 1)
    end
    local extra = classNote(classFilename)
    if extra then
        limitations[#limitations + 1] = extra
    end
    return {
        schema = M.SCHEMA,
        purpose = "warrior-capability-diagnostic",
        recommendationsChanged = false,
        recordedPlay = false,
        combatLog = "omitted",
        secrecy = canRead and "checked" or "withheld",
        capturedAt = gate(api, timePacked, 1),
        scope = {
            apiDump = "reckhou/WoWBlzCode 7245053a Forever 1.60.1.70658 dated 2026-10-28",
            reportedWowExe = "1.60.1.70862 product wowf (machine metadata, not a GetBuildInfo result)",
            parity = "unproven until the build fields below are read from this client",
        },
        lua = { version = api.luaVersion or "unavailable" },
        project = {
            id = api.projectId or "unavailable",
            camelotConstant = api.camelotConstant or "unavailable",
        },
        build = {
            version = gate(api, buildPacked, 1),
            build = gate(api, buildPacked, 2),
            date = gate(api, buildPacked, 3),
            interface = gate(api, buildPacked, 4),
            addonVersion = gate(api, versionPacked, 1),
        },
        cvar = {
            loadDeprecationFallbacks = gate(api, cvarPacked, 1),
        },
        restrictions = {
            hasSecretRestrictions = gate(api, restrictionsPacked.hasSecretRestrictions, 1),
            aurasSecret = gate(api, restrictionsPacked.aurasSecret, 1),
            cooldownsSecret = gate(api, restrictionsPacked.cooldownsSecret, 1),
            unitPowerSecret = gate(api, restrictionsPacked.unitPowerSecret, 1),
            scriptsDisallowedForBeta = gate(api, restrictionsPacked.scriptsDisallowedForBeta, 1),
            inCombatLockdown = gate(api, restrictionsPacked.inCombatLockdown, 1),
        },
        classFile = classFilename,
        presence = presence(api),
        spells = spellRows(api, canRead),
        limitations = limitations,
    }
end

function M.ClientApi(env)
    env = env or _G
    local secret = lookup(env, "issecretvalue")
    local function gatedGlobal(value)
        if type(secret) ~= "function" then
            return "unavailable"
        end
        if secret(value) then
            return "secret"
        end
        if value == nil then
            return "unavailable"
        end
        local kind = type(value)
        if kind == "number" or kind == "string" or kind == "boolean" then
            return value
        end
        return "unknown"
    end
    local luaVersion, projectId, camelotConstant = "unavailable", "unavailable", "unavailable"
    if type(secret) == "function" then
        luaVersion = gatedGlobal(env._VERSION)
        projectId = gatedGlobal(env.WOW_PROJECT_ID)
        camelotConstant = gatedGlobal(env.WOW_PROJECT_CAMELOT)
    end
    return {
        fn = function(name)
            return lookup(env, name)
        end,
        issecretvalue = type(secret) == "function" and secret or nil,
        luaVersion = luaVersion,
        projectId = projectId,
        camelotConstant = camelotConstant,
    }
end

function M.Run(api, write)
    local report = M.Diagnose(api)
    if type(write) == "function" then
        write(report)
    end
    return report
end

if ns then
    ns.WarriorCapability = M
end

return M
