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
            "IlvlTooltip_Safe.lua",
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

    it("normalizes nil and non-string tooltip messages", function()
        local tooltip = env:newTooltip("MessageNormalizationTooltip")
        tooltip:Show()

        tooltipView.SetTooltipLine(tooltip, "Player-1-00000030", nil, 1, 0.82, 0)
        assert.are.equal("iLvl: Unavailable", tooltip:GetLineText(1))

        tooltipView.SetTooltipLine(tooltip, "Player-1-00000030", 640.5, 0.2, 1, 0.2)
        assert.are.equal("iLvl: 640.5", tooltip:GetLineText(1))
    end)

    it("resolves guid from tooltip unit token", function()
        local guid = "Player-1-00000022"
        env:setUnit("target", {
            guid = guid,
            isPlayer = true,
            canInspect = true,
            inRange = true,
        })

        local tooltip = env:newTooltip("UnitTokenTooltip")
        tooltip:SetUnit("target")
        local unit, resolvedGuid = tooltipView.ResolveTooltipUnitAndGuid(tooltip)
        assert.are.equal("target", unit)
        assert.are.equal(guid, resolvedGuid)
    end)

    it("keeps tooltip data guid when no valid unit token is available", function()
        local guid = "Player-1-00000026"
        local tooltip = env:newTooltip("NoUnitTooltip")

        local unit, resolvedGuid = tooltipView.ResolveTooltipUnitAndGuid(tooltip, { guid = guid })
        assert.is_nil(unit)
        assert.are.equal(guid, resolvedGuid)
    end)

    it("maps tooltip data guid to a live unit token safely", function()
        local guid = "Player-1-00000027"
        env:setUnit("player", {
            guid = guid,
            isPlayer = true,
            canInspect = true,
            inRange = true,
        })

        local tooltip = env:newTooltip("DataGuidTooltip")
        local unit, resolvedGuid = tooltipView.ResolveTooltipUnitAndGuid(tooltip, { guid = guid })
        assert.are.equal("player", unit)
        assert.are.equal(guid, resolvedGuid)
    end)

    it("rejects UnitTokenFromGUID mapping when token guid mismatches", function()
        local guid = "Player-1-00000028"
        env:setUnit("target", {
            guid = "Player-1-99999999",
            isPlayer = true,
            canInspect = true,
            inRange = true,
        })
        _G.UnitTokenFromGUID = function()
            return "target"
        end

        local resolved = tooltipView.ResolveBestUnitTokenForGuid(guid, nil)
        assert.is_nil(resolved)
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

    it("ignores unsafe unit tokens returned by UnitTokenFromGUID", function()
        local guid = "Player-1-00000024"
        env:setUnit("target", {
            guid = guid,
            isPlayer = true,
            canInspect = true,
            inRange = true,
        })

        local originalUnitExists = _G.UnitExists
        _G.UnitExists = function(unit)
            if type(unit) ~= "string" then
                error("bad argument 1 to UnitExists", 2)
            end
            return originalUnitExists(unit)
        end
        _G.UnitTokenFromGUID = function()
            return {}
        end

        local resolved = tooltipView.ResolveBestUnitTokenForGuid(guid, nil)
        assert.are.equal("target", resolved)
    end)

    it("handles non-string tooltip unit tokens without throwing", function()
        local guid = "Player-1-00000025"
        env.worldMouseFocus = true
        env:setUnit("mouseover", {
            guid = guid,
            isPlayer = true,
            canInspect = true,
            inRange = true,
        })

        local tooltip = env:newTooltip("UnsafeTooltip")
        tooltip:SetUnit({})

        local unit, resolvedGuid = tooltipView.ResolveTooltipUnitAndGuid(tooltip, { guid = guid })
        assert.are.equal("mouseover", unit)
        assert.are.equal(guid, resolvedGuid)
    end)

    it("re-adds addon line when cached line handle is stale", function()
        local guid = "Player-1-00000029"
        local tooltip = env:newTooltip("StaleLineTooltip")
        tooltip:Show()

        tooltipView.SetTooltipLine(tooltip, guid, "Inspecting...", 1, 0.82, 0)
        assert.are.equal(1, tooltip:NumLines())
        assert.are.equal("iLvl: Inspecting...", tooltip:GetLineText(1))

        tooltip:ClearLines()
        tooltip:AddLine("Player Name", 1, 1, 1)

        tooltipView.SetTooltipLine(tooltip, guid, "Inspecting...", 1, 0.82, 0)
        assert.are.equal(2, tooltip:NumLines())
        assert.are.equal("Player Name", tooltip:GetLineText(1))
        assert.are.equal("iLvl: Inspecting...", tooltip:GetLineText(2))
    end)
end)
