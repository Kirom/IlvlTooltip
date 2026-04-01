local WowMock = require("spec.helpers.wow_mock")
local Loader = require("spec.helpers.addon_loader")

describe("IlvlTooltip tooltip view", function()
    local env
    local NS
    local tooltipView

    before_each(function()
        env = WowMock.new()
        env:installGlobals()
        NS = Loader.LoadModules({
            "IlvlTooltip_Constants.lua",
            "IlvlTooltip_TooltipView.lua",
        })
        tooltipView = NS.CreateTooltipView()
    end)

    it("adds and updates a single tooltip line without duplicates", function()
        local tooltip = env:newTooltip("UnitTooltip")
        tooltip:Show()

        tooltipView.SetTooltipLine(tooltip, "Player-1-00000021", "Inspecting...", 1, 0.82, 0)
        tooltipView.SetTooltipLine(tooltip, "Player-1-00000021", "Inspecting...", 1, 0.82, 0)
        assert.are.equal(1, tooltip:NumLines())
        assert.are.equal("iLvl: Inspecting...", tooltip:GetLineText(1))

        tooltipView.SetTooltipLine(tooltip, "Player-1-00000021", "620.0", 0.2, 1, 0.2)
        assert.are.equal(1, tooltip:NumLines())
        assert.are.equal("iLvl: 620.0", tooltip:GetLineText(1))
    end)

    it("resolves guid from tooltip data and maps to best unit token", function()
        local guid = "Player-1-00000022"
        env:setUnit("target", {
            guid = guid,
            isPlayer = true,
            canInspect = true,
            inRange = true,
        })

        local tooltip = env:newTooltip("NoUnitTooltip")
        local unit, resolvedGuid = tooltipView.ResolveTooltipUnitAndGuid(tooltip, { guid = guid })
        assert.are.equal("target", unit)
        assert.are.equal(guid, resolvedGuid)
    end)

    it("uses mouseover fallback when world frame owns focus", function()
        local guid = "Player-1-00000023"
        env.worldMouseFocus = true
        env:setUnit("mouseover", {
            guid = guid,
            isPlayer = true,
            canInspect = true,
            inRange = true,
        })

        local tooltip = env:newTooltip("WorldTooltip")
        local unit, resolvedGuid = tooltipView.ResolveTooltipUnitAndGuid(tooltip)
        assert.are.equal("mouseover", unit)
        assert.are.equal(guid, resolvedGuid)
    end)
end)
