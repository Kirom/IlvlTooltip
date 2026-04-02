local NS = IlvlTooltip or {}
IlvlTooltip = NS

local API = NS.Api

local Controller = NS.Controller or {}
NS.Controller = Controller

local started = false

local function isInInspectRange(unit)
    return unit and API.UnitExists(unit) and (not API.CheckInteractDistance or API.CheckInteractDistance(unit, 1))
end

local function isInspectableUnit(unit)
    return unit and API.UnitExists(unit) and API.UnitIsPlayer(unit) and API.CanInspect(unit) and isInInspectRange(unit)
end

function Controller.Start()
    if started then
        return
    end
    started = true

    local cache = NS.CreateCache()
    local tooltipView = NS.CreateTooltipView()
    local inspect

    local function updateVisibleTooltip(guid, fallbackMessage, r, g, b)
        local gameTooltip = API.GameTooltip
        if not gameTooltip or not gameTooltip:IsShown() then
            return
        end

        local currentUnit, currentGuid = tooltipView.ResolveTooltipUnitAndGuid(gameTooltip)
        if not currentGuid then
            currentGuid = tooltipView.GetRenderedGuid(gameTooltip)
        end
        if not currentGuid or currentGuid ~= guid then
            return
        end

        local cachedText, cr, cg, cb, hasCachedValue = cache.GetDisplay(guid)
        if hasCachedValue then
            tooltipView.SetTooltipLine(gameTooltip, guid, cachedText, cr, cg, cb)
            return
        end

        if inspect and inspect.IsWaiting() and inspect.GetPendingGuid() == guid and currentUnit and API.UnitExists(currentUnit) then
            tooltipView.SetTooltipLine(gameTooltip, guid, "Inspecting...", 1, 0.82, 0)
            return
        end

        if fallbackMessage then
            tooltipView.SetTooltipLine(gameTooltip, guid, fallbackMessage, r or 1, g or 0.3, b or 0.3)
        end
    end

    inspect = NS.CreateInspectOrchestrator({
        cache = cache,
        isInspectableUnit = isInspectableUnit,
        resolveBestUnitTokenForGuid = tooltipView.ResolveBestUnitTokenForGuid,
        onVisibleUpdate = updateVisibleTooltip,
    })

    local function shouldRefreshCacheState(cacheState)
        return cacheState == "none" or cacheState == "warm" or cacheState == "expired"
    end

    local function prefetchUnit(unit)
        if not unit or not API.UnitExists(unit) or not API.UnitIsPlayer(unit) then
            return
        end

        local guid = API.UnitGUID(unit)
        if not guid or not cache.IsPlayerGuid(guid) then
            return
        end

        if API.UnitIsUnit and API.UnitIsUnit(unit, "player") then
            return
        end

        local _, cacheState = cache.GetState(guid)
        if cacheState ~= "none" and cacheState ~= "expired" then
            return
        end

        if cache.IsInFailureBackoff(guid) or inspect.IsPendingOrQueued(guid) then
            return
        end

        if not isInspectableUnit(unit) then
            return
        end

        if inspect.TryReadLoadedItemLevel(unit, guid) then
            return
        end

        inspect.Request(unit, guid)
    end

    local function onTooltipSetUnit(tooltip, data)
        if not tooltip then
            return
        end

        cache.SweepIfNeeded(false, inspect.IsGuidProtected)

        local unit, guid = tooltipView.ResolveTooltipUnitAndGuid(tooltip, data)
        if not guid then
            return
        end

        if unit and API.UnitExists(unit) and not API.UnitIsPlayer(unit) and not cache.IsPlayerGuid(guid) then
            return
        end

        if (unit and API.UnitExists(unit) and API.UnitIsUnit(unit, "player")) or guid == API.UnitGUID("player") then
            local _, equipped = API.GetAverageItemLevel()
            if equipped and equipped > 0 then
                tooltipView.SetTooltipLine(tooltip, guid, string.format("%.1f", equipped), 0.2, 1, 0.2)
            end
            return
        end

        if not cache.IsPlayerGuid(guid) then
            return
        end

        local cachedText, cr, cg, cb, hasCachedValue, cacheState = cache.GetDisplay(guid)
        if hasCachedValue then
            tooltipView.SetTooltipLine(tooltip, guid, cachedText, cr, cg, cb)
        end

        local inspectable = isInspectableUnit(unit)
        local backoffActive = cache.IsInFailureBackoff(guid)
        local pendingOrQueued = inspect.IsPendingOrQueued(guid)

        if inspectable and not backoffActive and shouldRefreshCacheState(cacheState) then
            local fastPathHit = false

            if not pendingOrQueued then
                fastPathHit = inspect.TryReadLoadedItemLevel(unit, guid)
                if fastPathHit then
                    cachedText, cr, cg, cb, hasCachedValue = cache.GetDisplay(guid)
                    if hasCachedValue then
                        tooltipView.SetTooltipLine(tooltip, guid, cachedText, cr, cg, cb)
                    end
                    pendingOrQueued = false
                end
            end

            if not fastPathHit and inspect.Request(unit, guid, { priority = true }) then
                pendingOrQueued = true
            end
        end

        if hasCachedValue then
            return
        end

        if pendingOrQueued then
            tooltipView.SetTooltipLine(tooltip, guid, "Inspecting...", 1, 0.82, 0)
            return
        end

        if unit and API.UnitExists(unit) and not inspectable then
            tooltipView.SetTooltipLine(tooltip, guid, "Out of range", 1, 0.3, 0.3)
            return
        end

        tooltipView.SetTooltipLine(tooltip, guid, "Unavailable", 1, 0.3, 0.3)
    end

    local frame = API.CreateFrame and API.CreateFrame("Frame")
    if frame then
        frame:RegisterEvent("INSPECT_READY")
        frame:RegisterEvent("UPDATE_MOUSEOVER_UNIT")
        frame:RegisterEvent("PLAYER_TARGET_CHANGED")
        frame:SetScript("OnEvent", function(_, event, guid)
            if event == "INSPECT_READY" then
                inspect.OnInspectReady(guid)
                return
            end

            if event == "UPDATE_MOUSEOVER_UNIT" then
                prefetchUnit("mouseover")
                return
            end

            if event == "PLAYER_TARGET_CHANGED" then
                prefetchUnit("target")
            end
        end)
    end

    local tooltipDataProcessor = API.TooltipDataProcessor
    local enum = API.Enum
    if tooltipDataProcessor and tooltipDataProcessor.AddTooltipPostCall and enum and enum.TooltipDataType and enum.TooltipDataType.Unit then
        tooltipDataProcessor.AddTooltipPostCall(enum.TooltipDataType.Unit, function(tooltip, data)
            onTooltipSetUnit(tooltip, data)
        end)
    else
        local gameTooltip = API.GameTooltip
        if gameTooltip and gameTooltip.HookScript and gameTooltip.HasScript and gameTooltip:HasScript("OnTooltipSetUnit") then
            gameTooltip:HookScript("OnTooltipSetUnit", onTooltipSetUnit)
        end
    end

    Controller._state = {
        cache = cache,
        inspect = inspect,
        tooltipView = tooltipView,
        frame = frame,
        onTooltipSetUnit = onTooltipSetUnit,
    }
end
