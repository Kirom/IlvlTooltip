local WowMock = require("spec.helpers.wow_mock")
local Loader = require("spec.helpers.addon_loader")

describe("IlvlTooltip controller integration", function()
    local env
    local NS

    before_each(function()
        env = WowMock.new()
        env:installGlobals()
        NS = Loader.LoadAll()
    end)

    it("renders ilvl on unit tooltip immediately when inspect data is already loaded", function()
        local guid = "Player-1-00000031"
        env:setUnit("target", {
            guid = guid,
            isPlayer = true,
            canInspect = true,
            inRange = true,
        })
        env.gameTooltip:SetUnit("target")
        env:setInspectItemLevelFn(function()
            return nil, 638
        end)

        env:fireUnitTooltip(env.gameTooltip, { guid = guid })
        assert.are.equal("iLvl: 638.0", env.gameTooltip:GetLineText(1))
        assert.are.equal(0, #env.inspectRequests)

        env:fireEvent("INSPECT_READY", guid)
        assert.are.equal("iLvl: 638.0", env.gameTooltip:GetLineText(1))
    end)

    it("shows Inspecting then rerenders value when tooltip-triggered inspect completes", function()
        local guid = "Player-1-00000037"
        env:setUnit("target", {
            guid = guid,
            isPlayer = true,
            canInspect = true,
            inRange = true,
        })
        env.gameTooltip:SetUnit("target")
        env:setInspectItemLevelFn(function()
            return nil, nil
        end)

        env:fireUnitTooltip(env.gameTooltip, { guid = guid })
        assert.are.equal("iLvl: Inspecting...", env.gameTooltip:GetLineText(1))
        assert.are.equal(1, #env.inspectRequests)

        env:setInspectItemLevelFn(function()
            return nil, 647
        end)
        env:fireEvent("INSPECT_READY", guid)
        assert.are.equal("iLvl: 647.0", env.gameTooltip:GetLineText(1))
    end)

    it("renders own ilvl when tooltip resolves player via data guid token mapping", function()
        local playerGuid = "Player-1-00000030"
        env.playerIlvl = 633.7
        env:setUnit("player", {
            guid = playerGuid,
            isPlayer = true,
            canInspect = true,
            inRange = true,
        })
        env.gameTooltip:SetUnit(nil)

        env:fireUnitTooltip(env.gameTooltip, { guid = playerGuid })
        assert.are.equal("iLvl: 633.7", env.gameTooltip:GetLineText(1))
    end)

    it("ignores non-string tooltip data guid payloads", function()
        env.gameTooltip:SetUnit(nil)
        env:fireUnitTooltip(env.gameTooltip, { guid = {} })

        assert.is_nil(env.gameTooltip:GetLineText(1))
        assert.are.equal(0, #env.inspectRequests)
    end)

    it("refreshes warm cache immediately via fast path when inspect data is loaded", function()
        local guid = "Player-1-00000032"
        env:setUnit("target", {
            guid = guid,
            isPlayer = true,
            canInspect = true,
            inRange = true,
        })
        env.gameTooltip:SetUnit("target")

        env:setInspectItemLevelFn(function()
            return nil, 620
        end)
        env:fireUnitTooltip(env.gameTooltip, { guid = guid })
        assert.are.equal("iLvl: 620.0", env.gameTooltip:GetLineText(1))
        assert.are.equal(0, #env.inspectRequests)

        env:advance(NS.Constants.HOT_CACHE_TTL + 1)
        env:setInspectItemLevelFn(function()
            return nil, 622
        end)
        env:fireUnitTooltip(env.gameTooltip, { guid = guid })

        assert.are.equal("iLvl: 622.0", env.gameTooltip:GetLineText(1))
        assert.are.equal(0, #env.inspectRequests)
    end)

    it("prefetches target on event and serves cached ilvl on first tooltip", function()
        local guid = "Player-1-00000033"
        env:setUnit("target", {
            guid = guid,
            isPlayer = true,
            canInspect = true,
            inRange = true,
        })
        env:setInspectItemLevelFn(function()
            return nil, 645
        end)

        env:fireEvent("PLAYER_TARGET_CHANGED")
        assert.are.equal(1, #env.inspectRequests)

        env:fireEvent("INSPECT_READY", guid)

        env.gameTooltip:SetUnit("target")
        env:fireUnitTooltip(env.gameTooltip, { guid = guid })
        assert.are.equal("iLvl: 645.0", env.gameTooltip:GetLineText(1))
        assert.are.equal(1, #env.inspectRequests)
    end)

    it("does not enqueue duplicate inspect when prefetch is already pending", function()
        local guid = "Player-1-00000034"
        env:setUnit("target", {
            guid = guid,
            isPlayer = true,
            canInspect = true,
            inRange = true,
        })
        env.gameTooltip:SetUnit("target")
        env:setInspectItemLevelFn(function()
            return nil, nil
        end)

        env:fireEvent("PLAYER_TARGET_CHANGED")
        assert.are.equal(1, #env.inspectRequests)

        env:fireUnitTooltip(env.gameTooltip, { guid = guid })
        assert.are.equal("iLvl: Inspecting...", env.gameTooltip:GetLineText(1))
        assert.are.equal(1, #env.inspectRequests)
    end)

    it("rerenders inspected value when tooltip unit token becomes unavailable", function()
        local guid = "Player-1-00000035"
        env:setUnit("target", {
            guid = guid,
            isPlayer = true,
            canInspect = true,
            inRange = true,
        })
        env.gameTooltip:SetUnit("target")
        env:setInspectItemLevelFn(function()
            return nil, 639
        end)

        env:fireUnitTooltip(env.gameTooltip, { guid = guid })
        assert.are.equal("iLvl: 639.0", env.gameTooltip:GetLineText(1))
        assert.are.equal(0, #env.inspectRequests)

        env.gameTooltip:SetUnit(nil)
        env:fireEvent("INSPECT_READY", guid)
        assert.are.equal("iLvl: 639.0", env.gameTooltip:GetLineText(1))
    end)

    it("hooks OnTooltipSetUnit when TooltipDataProcessor is unavailable", function()
        env = WowMock.new()
        env:installGlobals()
        _G.TooltipDataProcessor = nil
        _G.Enum = nil
        NS = Loader.LoadAll()

        local guid = "Player-1-00000036"
        env:setUnit("target", {
            guid = guid,
            isPlayer = true,
            canInspect = true,
            inRange = true,
        })
        env.gameTooltip:SetUnit("target")
        env:setInspectItemLevelFn(function()
            return nil, 641
        end)

        env.gameTooltip:FireScript("OnTooltipSetUnit")
        assert.are.equal("iLvl: 641.0", env.gameTooltip:GetLineText(1))
        assert.are.equal(0, #env.inspectRequests)

        env:fireEvent("INSPECT_READY", guid)
        assert.are.equal("iLvl: 641.0", env.gameTooltip:GetLineText(1))
    end)
end)
