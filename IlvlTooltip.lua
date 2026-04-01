local ADDON_PREFIX = "iLvl:"
local HOT_CACHE_TTL = 60
local WARM_CACHE_TTL = 600
local INSPECT_COOLDOWN = 1.5
local INSPECT_TIMEOUT = 2.5
local RETRY_DELAY = 0.15
local MAX_RETRIES = 8
local FAILURE_BACKOFF_BASE = 2
local FAILURE_BACKOFF_MAX = 15
local CACHE_SWEEP_INTERVAL = 30

local cache = {}
local inspectQueue = {}
local queueHead = 1
local queueTail = 0
local queuedGuids = {}
local pendingUnit, pendingGuid
local waitingForInspect = false
local lastInspectTime = 0
local throttleTimer = nil
local pendingTimeoutTimer = nil
local lastCacheSweepAt = 0
local processQueue
local getBestUnitTokenForGuid

local frame = CreateFrame("Frame")
frame:RegisterEvent("INSPECT_READY")

local function startsWith(text, prefix)
    return text and prefix and text:sub(1, #prefix) == prefix
end

local function setTooltipLine(tooltip, message, r, g, b)
    if not tooltip then
        return
    end

    local lineText = string.format("%s %s", ADDON_PREFIX, message)
    local tooltipName = tooltip:GetName()
    local numLines = tooltip:NumLines()

    if tooltipName and numLines and numLines > 0 then
        for i = 1, numLines do
            local line = _G[tooltipName .. "TextLeft" .. i]
            if line then
                local text = line:GetText()
                if startsWith(text, ADDON_PREFIX) then
                    line:SetText(lineText)
                    line:SetTextColor(r or 1, g or 0.82, b or 0)
                    return
                end
            end
        end
    end

    tooltip:AddLine(lineText, r or 1, g or 0.82, b or 0)
    if tooltip:IsShown() then
        tooltip:Show()
    end
end

local function ensureCacheEntry(guid)
    if not guid then
        return nil
    end

    local entry = cache[guid]
    if entry then
        return entry
    end

    entry = {
        ilvl = nil,
        fetchedAt = 0,
        softExpireAt = 0,
        hardExpireAt = 0,
        lastAttemptAt = 0,
        failCount = 0,
        lastStatus = "none",
    }
    cache[guid] = entry
    return entry
end

local function isPlayerGuid(guid)
    return type(guid) == "string" and guid:match("^Player%-") ~= nil
end

local function getCacheState(guid)
    local entry = guid and cache[guid]
    if not entry then
        return nil, "none"
    end

    local ilvl = entry.ilvl
    if not ilvl or ilvl <= 0 then
        return entry, "none"
    end

    local now = GetTime()
    if now <= (entry.softExpireAt or 0) then
        return entry, "fresh"
    end

    if now <= (entry.hardExpireAt or 0) then
        return entry, "warm"
    end

    return entry, "expired"
end

local function getFailureBackoff(failCount)
    if not failCount or failCount <= 0 then
        return 0
    end

    local seconds = FAILURE_BACKOFF_BASE * (2 ^ (failCount - 1))
    return math.min(FAILURE_BACKOFF_MAX, seconds)
end

local function isInFailureBackoff(guid)
    local entry = guid and cache[guid]
    if not entry then
        return false, 0
    end

    if (entry.failCount or 0) <= 0 then
        return false, 0
    end

    if entry.lastStatus == "ok" or entry.lastStatus == "pending" then
        return false, 0
    end

    local backoff = getFailureBackoff(entry.failCount)
    if backoff <= 0 then
        return false, 0
    end

    local elapsed = GetTime() - (entry.lastAttemptAt or 0)
    local remaining = backoff - elapsed
    if remaining > 0 then
        return true, remaining
    end

    return false, 0
end

local function sweepCacheIfNeeded(force)
    local now = GetTime()
    if not force and (now - lastCacheSweepAt) < CACHE_SWEEP_INTERVAL then
        return
    end

    lastCacheSweepAt = now

    for guid, entry in pairs(cache) do
        if guid ~= pendingGuid and not queuedGuids[guid] then
            local hardExpireAt = entry.hardExpireAt or 0
            local hardExpired = hardExpireAt > 0 and now > hardExpireAt

            local inBackoff = false
            if (entry.failCount or 0) > 0 and entry.lastStatus ~= "ok" and entry.lastStatus ~= "pending" then
                local backoff = getFailureBackoff(entry.failCount)
                inBackoff = (now - (entry.lastAttemptAt or 0)) < backoff
            end

            local hasIlvl = entry.ilvl and entry.ilvl > 0
            if hardExpired and not inBackoff then
                cache[guid] = nil
            elseif not hasIlvl and not inBackoff and entry.lastStatus ~= "pending" then
                cache[guid] = nil
            end
        end
    end
end

local function markInspectAttempt(guid)
    local entry = ensureCacheEntry(guid)
    if not entry then
        return
    end

    entry.lastAttemptAt = GetTime()
    entry.lastStatus = "pending"
end

local function markInspectSuccess(guid, ilvl)
    local entry = ensureCacheEntry(guid)
    if not entry then
        return
    end

    local now = GetTime()
    entry.ilvl = ilvl
    entry.fetchedAt = now
    entry.softExpireAt = now + HOT_CACHE_TTL
    entry.hardExpireAt = now + WARM_CACHE_TTL
    entry.lastAttemptAt = now
    entry.failCount = 0
    entry.lastStatus = "ok"
end

local function markInspectFailure(guid, status)
    local entry = ensureCacheEntry(guid)
    if not entry then
        return
    end

    entry.lastAttemptAt = GetTime()
    entry.failCount = math.min((entry.failCount or 0) + 1, 10)
    entry.lastStatus = status or "failed"
end

local function getCachedDisplay(guid)
    local entry, state = getCacheState(guid)
    if not entry or not entry.ilvl or entry.ilvl <= 0 then
        return nil, nil, nil, nil, false, state
    end

    local stale = state ~= "fresh" or entry.lastStatus ~= "ok"
    local text = string.format("%.1f", entry.ilvl)
    if stale then
        text = text .. " (stale)"
        return text, 1, 0.82, 0, true, state
    end

    return text, 0.2, 1, 0.2, true, state
end

local function isInInspectRange(unit)
    return unit and UnitExists(unit) and (not CheckInteractDistance or CheckInteractDistance(unit, 1))
end

local function isInspectableUnit(unit)
    return unit and UnitExists(unit) and UnitIsPlayer(unit) and CanInspect(unit) and isInInspectRange(unit)
end

local function resolveTooltipUnitAndGuid(tooltip, data)
    local _, unit = tooltip.GetUnit and tooltip:GetUnit() or nil
    local guid = unit and UnitGUID(unit) or nil

    if (not unit or not UnitExists(unit)) and WorldFrame and WorldFrame.IsMouseMotionFocus and WorldFrame:IsMouseMotionFocus() and UnitExists("mouseover") then
        unit = "mouseover"
        guid = UnitGUID(unit)
    end

    if (not guid) and data and data.guid then
        guid = data.guid
    end

    if guid and (not unit or not UnitExists(unit)) then
        local bestUnit = getBestUnitTokenForGuid(guid, unit)
        if bestUnit and UnitExists(bestUnit) then
            unit = bestUnit
        end
    end

    return unit, guid
end

local function updateVisibleTooltip(guid, fallbackMessage, r, g, b)
    if not GameTooltip or not GameTooltip:IsShown() then
        return
    end

    local currentUnit, currentGuid = resolveTooltipUnitAndGuid(GameTooltip)
    if not currentGuid or currentGuid ~= guid then
        return
    end

    local cachedText, cr, cg, cb, hasCachedValue = getCachedDisplay(guid)
    if hasCachedValue then
        setTooltipLine(GameTooltip, cachedText, cr, cg, cb)
        return
    end

    if waitingForInspect and pendingGuid == guid and currentUnit and UnitExists(currentUnit) then
        setTooltipLine(GameTooltip, "Inspecting...", 1, 0.82, 0)
        return
    end

    if fallbackMessage then
        setTooltipLine(GameTooltip, fallbackMessage, r or 1, g or 0.3, b or 0.3)
    end
end

local function tryBuiltInInspectItemLevel(unit)
    if not (C_PaperDollInfo and C_PaperDollInfo.GetInspectItemLevel) then
        return nil
    end

    local ok, a, b = pcall(C_PaperDollInfo.GetInspectItemLevel, unit)
    if ok then
        if type(b) == "number" and b > 0 then
            return b
        end
        if type(a) == "number" and a > 0 then
            return a
        end
    end

    ok, a, b = pcall(C_PaperDollInfo.GetInspectItemLevel)
    if ok then
        if type(b) == "number" and b > 0 then
            return b
        end
        if type(a) == "number" and a > 0 then
            return a
        end
    end

    return nil
end

local inspectSlots = {
    1, 2, 3, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16, 17
}

local function tryManualInspectItemLevel(unit)
    if not unit or not UnitExists(unit) then
        return nil, true
    end

    local total = 0
    local count = 0
    local missingData = false

    for _, slot in ipairs(inspectSlots) do
        local link = GetInventoryItemLink(unit, slot)
        if link then
            local ilvl = GetDetailedItemLevelInfo(link)
            if ilvl and ilvl > 0 then
                total = total + ilvl
                count = count + 1
            else
                missingData = true
            end
        end
    end

    if count == 0 then
        return nil, missingData
    end

    return total / count, missingData
end

getBestUnitTokenForGuid = function(guid, fallbackUnit)
    if fallbackUnit and UnitExists(fallbackUnit) and UnitGUID(fallbackUnit) == guid then
        return fallbackUnit
    end

    if UnitTokenFromGUID then
        local byGuid = UnitTokenFromGUID(guid)
        if byGuid and UnitExists(byGuid) then
            return byGuid
        end
    end

    for _, unit in ipairs({ "mouseover", "target", "focus" }) do
        if UnitExists(unit) and UnitGUID(unit) == guid then
            return unit
        end
    end

    return fallbackUnit
end

local function cancelPendingTimeout()
    if pendingTimeoutTimer and pendingTimeoutTimer.Cancel then
        pendingTimeoutTimer:Cancel()
    end
    pendingTimeoutTimer = nil
end

local function finishInspect()
    cancelPendingTimeout()
    ClearInspectPlayer()
    waitingForInspect = false
    pendingUnit, pendingGuid = nil, nil
end

local function isInspectPendingOrQueued(guid)
    if not guid then
        return false
    end

    return (waitingForInspect and pendingGuid == guid) or queuedGuids[guid] == true
end

local function startInspect(unit, guid)
    cancelPendingTimeout()
    waitingForInspect = true
    pendingUnit = unit
    pendingGuid = guid
    markInspectAttempt(guid)
    lastInspectTime = GetTime()
    NotifyInspect(unit)

    pendingTimeoutTimer = C_Timer.NewTimer(INSPECT_TIMEOUT, function()
        if waitingForInspect and pendingGuid == guid then
            markInspectFailure(guid, "timeout")
            finishInspect()
            updateVisibleTooltip(guid, "Unavailable", 1, 0.3, 0.3)
            processQueue()
        end
    end)
end

processQueue = function()
    sweepCacheIfNeeded(false)

    if waitingForInspect then
        return
    end

    if queueHead > queueTail then
        return
    end

    local now = GetTime()
    local remaining = INSPECT_COOLDOWN - (now - lastInspectTime)
    if remaining > 0 then
        if not throttleTimer then
            throttleTimer = C_Timer.NewTimer(remaining, function()
                throttleTimer = nil
                processQueue()
            end)
        end
        return
    end

    while queueHead <= queueTail do
        local request = inspectQueue[queueHead]
        inspectQueue[queueHead] = nil
        queueHead = queueHead + 1

        if queueHead > queueTail then
            queueHead = 1
            queueTail = 0
        end

        queuedGuids[request.guid] = nil

        local backoffActive = isInFailureBackoff(request.guid)
        local bestUnit = getBestUnitTokenForGuid(request.guid, request.unit)

        if not backoffActive and isInspectableUnit(bestUnit) then
            startInspect(bestUnit, request.guid)
            return
        end
    end
end

local function enqueueInspect(unit, guid)
    if not guid or isInspectPendingOrQueued(guid) then
        return false
    end

    queueTail = queueTail + 1
    inspectQueue[queueTail] = { unit = unit, guid = guid }
    queuedGuids[guid] = true
    processQueue()
    return true
end

local function requestInspect(unit, guid)
    if not guid then
        return false
    end

    if isInspectPendingOrQueued(guid) then
        return false
    end

    local backoffActive = isInFailureBackoff(guid)
    if backoffActive then
        return false
    end

    return enqueueInspect(unit, guid)
end

local function resolveInspectWithRetry(guid, unit, attempt)
    if guid ~= pendingGuid then
        return
    end

    local bestUnit = getBestUnitTokenForGuid(guid, unit)
    local ilvl = tryBuiltInInspectItemLevel(bestUnit)
    local missingData = false

    if not ilvl then
        ilvl, missingData = tryManualInspectItemLevel(bestUnit)
    end

    if ilvl then
        markInspectSuccess(guid, ilvl)
        finishInspect()
        updateVisibleTooltip(guid)
        processQueue()
        return
    end

    if missingData and attempt < MAX_RETRIES then
        C_Timer.After(RETRY_DELAY, function()
            resolveInspectWithRetry(guid, bestUnit, attempt + 1)
        end)
        return
    end

    markInspectFailure(guid, "no_data")
    finishInspect()
    updateVisibleTooltip(guid, "Unavailable", 1, 0.3, 0.3)
    processQueue()
end

local function onTooltipSetUnit(tooltip, data)
    if not tooltip then
        return
    end

    sweepCacheIfNeeded(false)

    local unit, guid = resolveTooltipUnitAndGuid(tooltip, data)
    if not guid then
        return
    end

    if unit and UnitExists(unit) and not UnitIsPlayer(unit) and not isPlayerGuid(guid) then
        return
    end

    if (unit and UnitExists(unit) and UnitIsUnit(unit, "player")) or guid == UnitGUID("player") then
        local _, equipped = GetAverageItemLevel()
        if equipped and equipped > 0 then
            setTooltipLine(tooltip, string.format("%.1f", equipped), 0.2, 1, 0.2)
        end
        return
    end

    if not isPlayerGuid(guid) then
        return
    end

    local cachedText, cr, cg, cb, hasCachedValue, cacheState = getCachedDisplay(guid)
    if hasCachedValue then
        setTooltipLine(tooltip, cachedText, cr, cg, cb)
    end

    local inspectable = isInspectableUnit(unit)
    local backoffActive = isInFailureBackoff(guid)
    local pendingOrQueued = isInspectPendingOrQueued(guid)

    if inspectable and not backoffActive and (cacheState == "none" or cacheState == "warm" or cacheState == "expired") then
        if requestInspect(unit, guid) then
            pendingOrQueued = true
        end
    end

    if hasCachedValue then
        return
    end

    if pendingOrQueued then
        setTooltipLine(tooltip, "Inspecting...", 1, 0.82, 0)
        return
    end

    if unit and UnitExists(unit) and not inspectable then
        setTooltipLine(tooltip, "Out of range", 1, 0.3, 0.3)
        return
    end

    setTooltipLine(tooltip, "Unavailable", 1, 0.3, 0.3)
end

frame:SetScript("OnEvent", function(_, event, guid)
    if event == "INSPECT_READY" and waitingForInspect and guid == pendingGuid then
        resolveInspectWithRetry(guid, pendingUnit, 0)
    end
end)

local function registerTooltipHook()
    if TooltipDataProcessor and TooltipDataProcessor.AddTooltipPostCall and Enum and Enum.TooltipDataType and Enum.TooltipDataType.Unit then
        TooltipDataProcessor.AddTooltipPostCall(Enum.TooltipDataType.Unit, function(tooltip, data)
            onTooltipSetUnit(tooltip, data)
        end)
        return
    end

    if GameTooltip and GameTooltip.HookScript and GameTooltip.HasScript and GameTooltip:HasScript("OnTooltipSetUnit") then
        GameTooltip:HookScript("OnTooltipSetUnit", onTooltipSetUnit)
    end
end

registerTooltipHook()
