local NS = IlvlTooltip or {}
IlvlTooltip = NS

local C = NS.Constants
local API = NS.Api

local type = type

function NS.CreateInspectOrchestrator(deps)
    local cache = deps.cache
    local isInspectableUnit = deps.isInspectableUnit
    local resolveBestUnitTokenForGuid = deps.resolveBestUnitTokenForGuid
    local onVisibleUpdate = deps.onVisibleUpdate or function() end

    local inspectQueue = {}
    local queueHead = 1
    local queueTail = 0
    local queuedEntriesByGuid = {}
    local pendingUnit, pendingGuid
    local waitingForInspect = false
    local lastInspectTime = -(C.INSPECT_COOLDOWN or 0)
    local throttleTimer = nil
    local pendingTimeoutTimer = nil
    local inspectAttemptSerial = 0

    local service = {}
    local processQueue
    local resolveInspectWithRetry
    local completeSuccessfulInspect

    local function cancelPendingTimeout()
        if pendingTimeoutTimer and pendingTimeoutTimer.Cancel then
            pendingTimeoutTimer:Cancel()
        end
        pendingTimeoutTimer = nil
    end

    local function finishInspect()
        cancelPendingTimeout()
        if API.ClearInspectPlayer then
            API.ClearInspectPlayer()
        end
        waitingForInspect = false
        pendingUnit, pendingGuid = nil, nil
    end

    local function scheduleTimer(delay, fn)
        if API.C_Timer and API.C_Timer.NewTimer then
            return API.C_Timer.NewTimer(delay, fn)
        end
        return nil
    end

    local function scheduleAfter(delay, fn)
        if API.C_Timer and API.C_Timer.After then
            API.C_Timer.After(delay, fn)
            return
        end
        fn()
    end

    local function resetQueueIndicesIfEmpty()
        if queueHead > queueTail then
            queueHead = 1
            queueTail = 0
        end
    end

    local function enqueueAtBack(request)
        resetQueueIndicesIfEmpty()
        queueTail = queueTail + 1
        inspectQueue[queueTail] = request
    end

    local function enqueueAtFront(request)
        resetQueueIndicesIfEmpty()
        queueHead = queueHead - 1
        inspectQueue[queueHead] = request
    end

    local function tryBuiltInInspectItemLevel(unit)
        local paperDoll = API.C_PaperDollInfo
        if not (paperDoll and paperDoll.GetInspectItemLevel) then
            return nil
        end

        local ok, a, b = pcall(paperDoll.GetInspectItemLevel, unit)
        if ok then
            if type(b) == "number" and b > 0 then
                return b
            end
            if type(a) == "number" and a > 0 then
                return a
            end
        end

        ok, a, b = pcall(paperDoll.GetInspectItemLevel)
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

    local function tryManualInspectItemLevel(unit)
        if not unit or not API.UnitExists(unit) then
            return nil, true
        end

        local total = 0
        local count = 0
        local missingData = false

        for i = 1, #C.INSPECT_SLOTS do
            local slot = C.INSPECT_SLOTS[i]
            local link = API.GetInventoryItemLink(unit, slot)
            if link then
                local ilvl = API.GetDetailedItemLevelInfo(link)
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

    local function tryReadLoadedItemLevel(unit, guid)
        local bestUnit = resolveBestUnitTokenForGuid(guid, unit)
        local ilvl = tryBuiltInInspectItemLevel(bestUnit)
        local missingData = false

        if not ilvl then
            ilvl, missingData = tryManualInspectItemLevel(bestUnit)
        end

        return ilvl, missingData, bestUnit
    end

    function service.IsPendingOrQueued(guid)
        if not guid then
            return false
        end
        return (waitingForInspect and pendingGuid == guid) or queuedEntriesByGuid[guid] ~= nil
    end

    function service.IsGuidProtected(guid)
        return service.IsPendingOrQueued(guid)
    end

    function service.IsWaiting()
        return waitingForInspect
    end

    function service.GetPendingGuid()
        return pendingGuid
    end

    function service.TryReadLoadedItemLevel(unit, guid)
        if not guid then
            return false
        end

        if waitingForInspect and pendingGuid == guid then
            return false
        end

        local ilvl = tryReadLoadedItemLevel(unit, guid)
        if not ilvl then
            return false
        end

        cache.MarkSuccess(guid, ilvl)
        return true, ilvl
    end

    completeSuccessfulInspect = function(guid, ilvl)
        cache.MarkSuccess(guid, ilvl)
        finishInspect()
        onVisibleUpdate(guid)
        processQueue()
    end

    local function scheduleEarlyProbe(guid, attemptSerial, attempt)
        if attempt > C.EARLY_PROBE_ATTEMPTS then
            return
        end

        scheduleAfter(C.EARLY_PROBE_DELAY, function()
            if not waitingForInspect or pendingGuid ~= guid or inspectAttemptSerial ~= attemptSerial then
                return
            end

            local ilvl = tryReadLoadedItemLevel(pendingUnit, guid)
            if ilvl then
                completeSuccessfulInspect(guid, ilvl)
                return
            end

            scheduleEarlyProbe(guid, attemptSerial, attempt + 1)
        end)
    end

    local function startInspect(unit, guid)
        cancelPendingTimeout()
        waitingForInspect = true
        pendingUnit = unit
        pendingGuid = guid
        inspectAttemptSerial = inspectAttemptSerial + 1
        local currentAttemptSerial = inspectAttemptSerial
        cache.MarkAttempt(guid)
        lastInspectTime = API.GetTime()
        if API.NotifyInspect then
            API.NotifyInspect(unit)
        end

        scheduleEarlyProbe(guid, currentAttemptSerial, 1)

        pendingTimeoutTimer = scheduleTimer(C.INSPECT_TIMEOUT, function()
            if waitingForInspect and pendingGuid == guid then
                cache.MarkFailure(guid, "timeout")
                finishInspect()
                onVisibleUpdate(guid, "Unavailable", 1, 0.3, 0.3)
                processQueue()
            end
        end)
    end

    processQueue = function()
        cache.SweepIfNeeded(false, service.IsGuidProtected)

        if waitingForInspect then
            return
        end

        if queueHead > queueTail then
            return
        end

        local now = API.GetTime()
        local remaining = C.INSPECT_COOLDOWN - (now - lastInspectTime)
        if remaining > 0 then
            if not throttleTimer then
                throttleTimer = scheduleTimer(remaining, function()
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

            if request and not request.cancelled then
                if queuedEntriesByGuid[request.guid] == request then
                    queuedEntriesByGuid[request.guid] = nil
                end

                local backoffActive = cache.IsInFailureBackoff(request.guid)
                local bestUnit = resolveBestUnitTokenForGuid(request.guid, request.unit)
                if not backoffActive and isInspectableUnit(bestUnit) then
                    resetQueueIndicesIfEmpty()
                    startInspect(bestUnit, request.guid)
                    return
                end
            end

            resetQueueIndicesIfEmpty()
        end
    end

    local function enqueueInspect(unit, guid, priority)
        if not guid or (waitingForInspect and pendingGuid == guid) then
            return false
        end

        local existing = queuedEntriesByGuid[guid]
        if existing then
            if not (priority and not existing.priority) then
                return false
            end
            existing.cancelled = true
        end

        local request = {
            unit = unit,
            guid = guid,
            priority = priority == true,
            cancelled = false,
        }
        queuedEntriesByGuid[guid] = request

        if request.priority then
            enqueueAtFront(request)
        else
            enqueueAtBack(request)
        end

        processQueue()
        return true
    end

    function service.Request(unit, guid, options)
        if not guid or service.IsPendingOrQueued(guid) then
            local requestedPriority = false
            if type(options) == "table" then
                requestedPriority = options.priority == true
            elseif options == true then
                requestedPriority = true
            end

            if requestedPriority then
                return enqueueInspect(unit, guid, true)
            end

            return false
        end

        local backoffActive = cache.IsInFailureBackoff(guid)
        if backoffActive then
            return false
        end

        local priority = false
        if type(options) == "table" then
            priority = options.priority == true
        elseif options == true then
            priority = true
        end

        return enqueueInspect(unit, guid, priority)
    end

    resolveInspectWithRetry = function(guid, unit, attempt)
        if guid ~= pendingGuid then
            return
        end

        local ilvl, missingData, bestUnit = tryReadLoadedItemLevel(unit, guid)

        if ilvl then
            completeSuccessfulInspect(guid, ilvl)
            return
        end

        if missingData and attempt < C.MAX_RETRIES then
            scheduleAfter(C.RETRY_DELAY, function()
                resolveInspectWithRetry(guid, bestUnit, attempt + 1)
            end)
            return
        end

        cache.MarkFailure(guid, "no_data")
        finishInspect()
        onVisibleUpdate(guid, "Unavailable", 1, 0.3, 0.3)
        processQueue()
    end

    function service.OnInspectReady(guid)
        if waitingForInspect and guid == pendingGuid then
            resolveInspectWithRetry(guid, pendingUnit, 0)
        end
    end

    function service.ProcessQueue()
        processQueue()
    end

    return service
end
