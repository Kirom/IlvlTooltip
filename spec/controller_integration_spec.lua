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

    it("renders inspected ilvl on unit tooltip", function()
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
        assert.are.equal("iLvl: Inspecting...", env.gameTooltip:GetLineText(1))

        env:fireEvent("INSPECT_READY", guid)
        assert.are.equal("iLvl: 638.0", env.gameTooltip:GetLineText(1))
    end)

    it("keeps stale cache visible and requests refresh in warm state", function()
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
        env:fireEvent("INSPECT_READY", guid)
        assert.are.equal("iLvl: 620.0", env.gameTooltip:GetLineText(1))

        env:advance(NS.Constants.HOT_CACHE_TTL + 1)
        env:setInspectItemLevelFn(function()
            return nil, 622
        end)
        env:fireUnitTooltip(env.gameTooltip, { guid = guid })

        local lineText = env.gameTooltip:GetLineText(1)
        assert.is_true(lineText:find("%(stale%)", 1, true) ~= nil)
        assert.is_true(#env.inspectRequests >= 2)
    end)
end)
