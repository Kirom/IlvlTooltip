local WowMock = require("spec.helpers.wow_mock")
local Loader = require("spec.helpers.addon_loader")

describe("IlvlTooltip settings", function()
    local env
    local NS

    before_each(function()
        env = WowMock.new()
        env:installGlobals()
        _G.IlvlTooltipDB = nil

        NS = Loader.LoadModules({
            "IlvlTooltip_Constants.lua",
            "IlvlTooltip_Settings.lua",
            "IlvlTooltip_Safe.lua",
            "IlvlTooltip_Cache.lua",
        })
    end)

    it("initializes default ttl values", function()
        NS.Settings.Initialize()

        assert.are.equal(NS.Constants.HOT_CACHE_TTL, NS.Settings.GetHotCacheTTL())
        assert.are.equal(NS.Constants.WARM_CACHE_TTL, NS.Settings.GetWarmCacheTTL())
    end)

    it("sanitizes persisted settings and keeps warm ttl above hot ttl", function()
        _G.IlvlTooltipDB = {
            hotCacheTTL = -40,
            warmCacheTTL = 5,
        }

        NS.Settings.Initialize()

        assert.are.equal(NS.Constants.HOT_CACHE_TTL_MIN, NS.Settings.GetHotCacheTTL())
        assert.is_true(NS.Settings.GetWarmCacheTTL() >= NS.Settings.GetHotCacheTTL())
    end)

    it("keeps ttl pair consistent when changed through setters", function()
        NS.Settings.Initialize()

        NS.Settings.SetWarmCacheTTL(120)
        NS.Settings.SetHotCacheTTL(180)
        assert.are.equal(180, NS.Settings.GetHotCacheTTL())
        assert.are.equal(180, NS.Settings.GetWarmCacheTTL())

        NS.Settings.SetHotCacheTTL(90)
        NS.Settings.SetWarmCacheTTL(70)
        assert.are.equal(70, NS.Settings.GetHotCacheTTL())
        assert.are.equal(70, NS.Settings.GetWarmCacheTTL())
    end)

    it("applies configured ttl values in cache state transitions", function()
        NS.Settings.Initialize()
        NS.Settings.SetHotCacheTTL(20)
        NS.Settings.SetWarmCacheTTL(40)

        local cache = NS.CreateCache()
        local guid = "Player-1-00000088"
        cache.MarkSuccess(guid, 625.2)

        local _, stateFresh = cache.GetState(guid)
        assert.are.equal("fresh", stateFresh)

        env:advance(20.1)
        local _, stateWarm = cache.GetState(guid)
        assert.are.equal("warm", stateWarm)

        env:advance(20.1)
        local _, stateExpired = cache.GetState(guid)
        assert.are.equal("expired", stateExpired)
    end)
end)
