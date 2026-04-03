local NS = IlvlTooltip or {}
IlvlTooltip = NS

local C = NS.Constants
local API = NS.Api
local Safe = NS.Safe
local CACHE_STATUS = C.CACHE_STATUS

local math_min = math.min
local string_format = string.format
local type = type

local function getHotCacheTTL()
    local settings = NS.Settings
    if settings and settings.GetHotCacheTTL then
        local ttl = settings.GetHotCacheTTL()
        if type(ttl) == "number" and ttl > 0 then
            return ttl
        end
    end

    return C.HOT_CACHE_TTL
end

local function getWarmCacheTTL(hotCacheTTL)
    local settings = NS.Settings
    if settings and settings.GetWarmCacheTTL then
        local ttl = settings.GetWarmCacheTTL()
        if type(ttl) == "number" and ttl > 0 then
            if ttl < hotCacheTTL then
                return hotCacheTTL
            end
            return ttl
        end
    end

    if C.WARM_CACHE_TTL < hotCacheTTL then
        return hotCacheTTL
    end
    return C.WARM_CACHE_TTL
end

local function isValidIlvl(value)
    if type(value) ~= "number" then
        return false
    end

    if value <= 0 then
        return false
    end

    if value ~= value or value == math.huge or value == -math.huge then
        return false
    end

    return true
end

function NS.CreateCache()
    local cache = {}
    local lastCacheSweepAt = 0

    local service = {}

    local function ensureCacheEntry(guid)
        if not Safe.IsGuid(guid) then
            return nil
        end

        local entry = cache[guid]
        if entry then
            return entry
        end

        entry = {
            ilvl = nil,
            fetchedAt = 0,
            lastAttemptAt = 0,
            failCount = 0,
            lastStatus = CACHE_STATUS.NONE,
        }
        cache[guid] = entry
        return entry
    end

    function service.IsPlayerGuid(guid)
        return Safe.IsPlayerGuid(guid)
    end

    function service.GetState(guid)
        if not Safe.IsGuid(guid) then
            return nil, CACHE_STATUS.NONE
        end

        local entry = guid and cache[guid]
        if not entry then
            return nil, CACHE_STATUS.NONE
        end

        local ilvl = entry.ilvl
        if not isValidIlvl(ilvl) then
            return entry, CACHE_STATUS.NONE
        end

        local now = API.GetTime()
        local fetchedAt = entry.fetchedAt
        if type(fetchedAt) ~= "number" then
            return entry, "expired"
        end

        local hotCacheTTL = getHotCacheTTL()
        local warmCacheTTL = getWarmCacheTTL(hotCacheTTL)
        if now <= (fetchedAt + hotCacheTTL) then
            return entry, "fresh"
        end

        if now <= (fetchedAt + warmCacheTTL) then
            return entry, "warm"
        end

        return entry, "expired"
    end

    function service.GetFailureBackoff(failCount)
        if not failCount or failCount <= 0 then
            return 0
        end

        local seconds = C.FAILURE_BACKOFF_BASE * (2 ^ (failCount - 1))
        return math_min(C.FAILURE_BACKOFF_MAX, seconds)
    end

    function service.IsInFailureBackoff(guid)
        if not Safe.IsGuid(guid) then
            return false, 0
        end

        local entry = guid and cache[guid]
        if not entry then
            return false, 0
        end

        if (entry.failCount or 0) <= 0 then
            return false, 0
        end

        if entry.lastStatus == CACHE_STATUS.OK or entry.lastStatus == CACHE_STATUS.PENDING then
            return false, 0
        end

        local backoff = service.GetFailureBackoff(entry.failCount)
        if backoff <= 0 then
            return false, 0
        end

        local elapsed = API.GetTime() - (entry.lastAttemptAt or 0)
        local remaining = backoff - elapsed
        if remaining > 0 then
            return true, remaining
        end

        return false, 0
    end

    function service.SweepIfNeeded(force, isProtectedGuid)
        local now = API.GetTime()
        if not force and (now - lastCacheSweepAt) < C.CACHE_SWEEP_INTERVAL then
            return
        end

        lastCacheSweepAt = now
        local hotCacheTTL = getHotCacheTTL()
        local warmCacheTTL = getWarmCacheTTL(hotCacheTTL)

        for guid, entry in pairs(cache) do
            local protected = false
            if isProtectedGuid then
                protected = isProtectedGuid(guid) == true
            end

            if not protected then
                local fetchedAt = entry.fetchedAt
                local hardExpired = type(fetchedAt) ~= "number" or now > (fetchedAt + warmCacheTTL)

                local inBackoff = false
                if (entry.failCount or 0) > 0 and entry.lastStatus ~= CACHE_STATUS.OK and entry.lastStatus ~= CACHE_STATUS.PENDING then
                    local backoff = service.GetFailureBackoff(entry.failCount)
                    inBackoff = (now - (entry.lastAttemptAt or 0)) < backoff
                end

                local hasIlvl = isValidIlvl(entry.ilvl)
                if hardExpired and not inBackoff then
                    cache[guid] = nil
                elseif not hasIlvl and not inBackoff and entry.lastStatus ~= CACHE_STATUS.PENDING then
                    cache[guid] = nil
                end
            end
        end
    end

    function service.MarkAttempt(guid)
        local entry = ensureCacheEntry(guid)
        if not entry then
            return
        end

        entry.lastAttemptAt = API.GetTime()
        entry.lastStatus = CACHE_STATUS.PENDING
    end

    function service.MarkSuccess(guid, ilvl)
        local entry = ensureCacheEntry(guid)
        if not entry then
            return false
        end

        if not isValidIlvl(ilvl) then
            return false
        end

        local now = API.GetTime()
        entry.ilvl = ilvl
        entry.fetchedAt = now
        entry.lastAttemptAt = now
        entry.failCount = 0
        entry.lastStatus = CACHE_STATUS.OK
        return true
    end

    function service.MarkFailure(guid, status)
        local entry = ensureCacheEntry(guid)
        if not entry then
            return
        end

        entry.lastAttemptAt = API.GetTime()
        entry.failCount = math_min((entry.failCount or 0) + 1, 10)
        entry.lastStatus = status or CACHE_STATUS.FAILED
    end

    function service.GetDisplay(guid)
        local entry, state = service.GetState(guid)
        if not entry or not isValidIlvl(entry.ilvl) then
            return nil, nil, nil, nil, false, state
        end

        local stale = state ~= "fresh" or entry.lastStatus ~= CACHE_STATUS.OK
        local text = string_format("%.1f", entry.ilvl)
        if stale then
            return text .. " (stale)", 1, 0.82, 0, true, state
        end

        return text, 0.2, 1, 0.2, true, state
    end

    return service
end
