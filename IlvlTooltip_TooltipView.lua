local NS = IlvlTooltip or {}
IlvlTooltip = NS

local C = NS.Constants
local API = NS.Api

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

        if renderState and renderState.guid == guid and renderState.text == lineText and renderState.r == red and renderState.g == green and renderState.b == blue then
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
        if fallbackUnit and API.UnitExists(fallbackUnit) and API.UnitGUID(fallbackUnit) == guid then
            return fallbackUnit
        end

        if API.UnitTokenFromGUID then
            local byGuid = API.UnitTokenFromGUID(guid)
            if byGuid and API.UnitExists(byGuid) then
                return byGuid
            end
        end

        for i = 1, #C.GUID_FALLBACK_UNITS do
            local unit = C.GUID_FALLBACK_UNITS[i]
            if API.UnitExists(unit) and API.UnitGUID(unit) == guid then
                return unit
            end
        end

        return fallbackUnit
    end

    function service.ResolveTooltipUnitAndGuid(tooltip, data)
        local _, unit = tooltip.GetUnit and tooltip:GetUnit() or nil
        local guid = unit and API.UnitGUID(unit) or nil

        local worldFrame = API.WorldFrame
        if (not unit or not API.UnitExists(unit)) and worldFrame and worldFrame.IsMouseMotionFocus and worldFrame:IsMouseMotionFocus() and API.UnitExists("mouseover") then
            unit = "mouseover"
            guid = API.UnitGUID(unit)
        end

        if (not guid) and data and data.guid then
            guid = data.guid
        end

        if guid and (not unit or not API.UnitExists(unit)) then
            local bestUnit = service.ResolveBestUnitTokenForGuid(guid, unit)
            if bestUnit and API.UnitExists(bestUnit) then
                unit = bestUnit
            end
        end

        return unit, guid
    end

    return service
end
