local WowMock = require("spec.helpers.wow_mock")
local Loader = require("spec.helpers.addon_loader")

describe("IlvlTooltip cache service", function()
    local env
    local NS
    local cache

    before_each(function()
        env = WowMock.new()
        env:installGlobals()
        NS = Loader.LoadModules({
            "IlvlTooltip_Constants.lua",
            "IlvlTooltip_Safe.lua",
            "IlvlTooltip_Cache.lua",
        })
        cache = NS.CreateCache()
    end)

    it("transitions from fresh to warm to expired", function()
        local guid = "Player-1-00000002"
        cache.MarkSuccess(guid, 620.5)

        local text, _, _, _, hasValue, state = cache.GetDisplay(guid)
        assert.is_true(hasValue)
        assert.are.equal("620.5", text)
        assert.are.equal("fresh", state)

        env:advance(NS.Constants.HOT_CACHE_TTL + 0.01)
        local _, _, _, _, _, warmState = cache.GetDisplay(guid)
        assert.are.equal("warm", warmState)

        env:advance((NS.Constants.WARM_CACHE_TTL - NS.Constants.HOT_CACHE_TTL) + 0.01)
        local _, _, _, _, _, expiredState = cache.GetDisplay(guid)
        assert.are.equal("expired", expiredState)
    end)

    it("marks warm cached values as stale", function()
        local guid = "Player-1-00000003"
        cache.MarkSuccess(guid, 634)
        env:advance(NS.Constants.HOT_CACHE_TTL + 0.01)

        local text, _, _, _, hasValue, state = cache.GetDisplay(guid)
        assert.is_true(hasValue)
        assert.is_true(text:find("(stale)", 1, true) ~= nil)
        assert.are.equal("warm", state)
    end)

    it("applies capped exponential backoff", function()
        local guid = "Player-1-00000004"
        for _ = 1, 10 do
            cache.MarkFailure(guid, "timeout")
        end

        local active, remaining = cache.IsInFailureBackoff(guid)
        assert.is_true(active)
        assert.is_true(remaining <= NS.Constants.FAILURE_BACKOFF_MAX + 0.001)

        env:advance(NS.Constants.FAILURE_BACKOFF_MAX + 0.1)
        local activeAfter = cache.IsInFailureBackoff(guid)
        assert.is_false(activeAfter)
    end)

    it("sweeps expired entries when unprotected", function()
        local guid = "Player-1-00000005"
        cache.MarkSuccess(guid, 600)
        env:advance(NS.Constants.WARM_CACHE_TTL + 0.1)

        cache.SweepIfNeeded(true, function()
            return false
        end)

        local entry = cache.GetState(guid)
        assert.is_nil(entry)
    end)

    it("keeps protected entries during sweep", function()
        local guid = "Player-1-00000006"
        cache.MarkSuccess(guid, 600)
        env:advance(NS.Constants.WARM_CACHE_TTL + 0.1)

        cache.SweepIfNeeded(true, function(candidate)
            return candidate == guid
        end)

        local entry, state = cache.GetState(guid)
        assert.is_not_nil(entry)
        assert.are.equal("expired", state)
    end)

    it("ignores non-string guid inputs on writes", function()
        cache.MarkSuccess({}, 601)
        cache.MarkAttempt({})
        cache.MarkFailure({}, "timeout")

        local entry, state = cache.GetState({})
        assert.is_nil(entry)
        assert.are.equal("none", state)
    end)
end)
