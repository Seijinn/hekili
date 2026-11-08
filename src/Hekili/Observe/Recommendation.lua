-- Observe/Recommendation.lua
-- Read-only view of the primary display's already published recommendation.
-- Does not call Update, write the profile database, or register events.

local function withheld()
    return { spellId = "unavailable", keybind = "unavailable", actionKey = "unavailable" }
end

--- `engine` is Hekili.Engine. `secret` is issecretvalue or nil.
--- A missing secrecy test withholds the fields. This does not refresh the display.
local function displayed(engine, secret)
    if type(secret) ~= "function" then
        return withheld()
    end
    local primary = type(engine) == "table" and engine.Output and engine.Output.Primary
    if type(primary) ~= "table" or type(primary.count) ~= "number" or primary.count < 1 then
        return withheld()
    end
    local rec = primary.recs and primary.recs[1]
    if type(rec) ~= "table" then
        return withheld()
    end
    local function plain(value)
        if secret(value) then
            return "secret"
        end
        if value == nil then
            return "unavailable"
        end
        local kind = type(value)
        if kind == "number" or kind == "string" then
            return value
        end
        return "unknown"
    end
    return {
        spellId = plain(rec.actionID),
        keybind = plain(rec.keybind),
        actionKey = plain(rec.actionName),
    }
end

if type(Hekili) == "table" then
    function Hekili:GetDisplayedRecommendation()
        local secret = _G.issecretvalue
        return displayed(Hekili.Engine, secret)
    end
end

return displayed
