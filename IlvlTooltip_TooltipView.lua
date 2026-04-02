local NS = IlvlTooltip or {}
IlvlTooltip = NS

local C = NS.Constants
local API = NS.Api
local Safe = NS.Safe

local setmetatable = setmetatable
local string_sub = string.sub

function NS.CreateTooltipView()
    local tooltipLineCache = setmetatable({}, { __mode = "k" })
    local tooltipRenderState = setmetatable({}, { __mode = "k" })

    local service = {}

    local function startsWith(text, prefix)
        return text and prefix and string_sub(text, 1, #prefix) == prefix
    end

    function service.SetTooltipLine(tooltip, guid, message, r, g, b)
        if not tooltip then
            return
        end

        local red = r or 1
        local green = g or 0.82
        local blue = b or 0
        local lineText = C.ADDON_PREFIX .. " " .. message
        local cachedLine = tooltipLineCache[tooltip]
        local renderState = tooltipRenderState[tooltip]

        if renderState and Safe.GuidEquals(renderState.guid, guid) and renderState.text == lineText and renderState.r == red and renderState.g == green and renderState.b == blue then
            if cachedLine and cachedLine.GetText and cachedLine:GetText() == lineText then
                return
            end
        end

        if cachedLine then
            local cachedText = cachedLine:GetText()
            if startsWith(cachedText, C.ADDON_PREFIX) then
                cachedLine:SetText(lineText)
                cachedLine:SetTextColor(red, green, blue)

                if not renderState then
                    renderState = {}
                    tooltipRenderState[tooltip] = renderState
                end
                renderState.guid = guid
                renderState.text = lineText
                renderState.r = red
                renderState.g = green
                renderState.b = blue
                return
            end

            tooltipLineCache[tooltip] = nil
        end

        local tooltipName = tooltip:GetName()
        local numLines = tooltip:NumLines()

        if tooltipName and numLines and numLines > 0 then
            for i = 1, numLines do
                local line = _G[tooltipName .. "TextLeft" .. i]
                if line then
                    local text = line:GetText()
                    if startsWith(text, C.ADDON_PREFIX) then
                        line:SetText(lineText)
                        line:SetTextColor(red, green, blue)
                        tooltipLineCache[tooltip] = line

                        if not renderState then
                            renderState = {}
                            tooltipRenderState[tooltip] = renderState
                        end
                        renderState.guid = guid
                        renderState.text = lineText
                        renderState.r = red
                        renderState.g = green
                        renderState.b = blue
                        return
                    end
                end
            end
        end

        tooltip:AddLine(lineText, red, green, blue)
        if tooltipName then
            local lastLine = _G[tooltipName .. "TextLeft" .. tooltip:NumLines()]
            if lastLine then
                tooltipLineCache[tooltip] = lastLine
            end
        end

        if not renderState then
            renderState = {}
            tooltipRenderState[tooltip] = renderState
        end
        renderState.guid = guid
        renderState.text = lineText
        renderState.r = red
        renderState.g = green
        renderState.b = blue

        if tooltip:IsShown() then
            tooltip:Show()
        end
    end

    function service.GetRenderedGuid(tooltip)
        if not tooltip then
            return nil
        end

        local renderState = tooltipRenderState[tooltip]
        if not renderState or not renderState.guid then
            return nil
        end

        local cachedLine = tooltipLineCache[tooltip]
        if cachedLine and cachedLine.GetText and startsWith(cachedLine:GetText(), C.ADDON_PREFIX) then
            return renderState.guid
        end

        local tooltipName = tooltip:GetName()
        local numLines = tooltip:NumLines()
        if tooltipName and numLines and numLines > 0 then
            for i = 1, numLines do
                local line = _G[tooltipName .. "TextLeft" .. i]
                if line then
                    local text = line:GetText()
                    if startsWith(text, C.ADDON_PREFIX) then
                        tooltipLineCache[tooltip] = line
                        return renderState.guid
                    end
                end
            end
        end

        return nil
    end

    function service.ResolveBestUnitTokenForGuid(guid, fallbackUnit)
        if not Safe.IsGuid(guid) then
            return fallbackUnit
        end

        local byGuid = Safe.UnitTokenFromGUID(guid)
        if byGuid then
            return byGuid
        end

        if fallbackUnit and Safe.UnitExists(fallbackUnit) and Safe.GuidEquals(Safe.UnitGUID(fallbackUnit), guid) then
            return fallbackUnit
        end

        for i = 1, #C.GUID_FALLBACK_UNITS do
            local unit = C.GUID_FALLBACK_UNITS[i]
            if Safe.UnitExists(unit) and Safe.GuidEquals(Safe.UnitGUID(unit), guid) then
                return unit
            end
        end

        return fallbackUnit
    end

    function service.ResolveTooltipUnitAndGuid(tooltip, data)
        local _, unit = tooltip.GetUnit and tooltip:GetUnit() or nil
        if not Safe.UnitExists(unit) then
            unit = nil
        end

        local guid = unit and Safe.UnitGUID(unit) or nil

        local worldFrame = API.WorldFrame
        if (not unit or not Safe.UnitExists(unit)) and worldFrame and worldFrame.IsMouseMotionFocus and worldFrame:IsMouseMotionFocus() and Safe.UnitExists("mouseover") then
            unit = "mouseover"
            guid = Safe.UnitGUID(unit)
        end

        if (not unit or not Safe.UnitExists(unit)) and not guid and data and Safe.IsGuid(data.guid) then
            local unitFromDataGuid = Safe.UnitTokenFromGUID(data.guid)
            if unitFromDataGuid then
                unit = unitFromDataGuid
                guid = Safe.UnitGUID(unit)
            end
        end

        if guid and (not unit or not Safe.UnitExists(unit)) then
            local bestUnit = service.ResolveBestUnitTokenForGuid(guid, unit)
            if bestUnit and Safe.UnitExists(bestUnit) then
                unit = bestUnit
            end
        end

        return unit, guid
    end

    return service
end
