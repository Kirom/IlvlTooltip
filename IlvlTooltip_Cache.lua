local NS = IlvlTooltip or {}
IlvlTooltip = NS

local C = NS.Constants
local API = NS.Api
local Safe = NS.Safe

local math_min = math.min
local string_format = string.format
local type = type

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
            softExpireAt = 0,
            hardExpireAt = 0,
            lastAttemptAt = 0,
            failCount = 0,
            lastStatus = "none",
        }
        cache[guid] = entry
        return entry
    end

    function service.IsPlayerGuid(guid)
        return Safe.IsPlayerGuid(guid)
    end

    function service.GetState(guid)
        if not Safe.IsGuid(guid) then
            return nil, "none"
        end

        local entry = guid and cache[guid]
        if not entry then
            return nil, "none"
        end

        local ilvl = entry.ilvl
        if not isValidIlvl(ilvl) then
            return entry, "none"
        end

        local now = API.GetTime()
        if now <= (entry.softExpireAt or 0) then
            return entry, "fresh"
        end

        if now <= (entry.hardExpireAt or 0) then
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

        if entry.lastStatus == "ok" or entry.lastStatus == "pending" then
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

        for guid, entry in pairs(cache) do
            local protected = false
            if isProtectedGuid then
                protected = isProtectedGuid(guid) == true
            end

            if not protected then
                local hardExpireAt = entry.hardExpireAt or 0
                local hardExpired = hardExpireAt > 0 and now > hardExpireAt

                local inBackoff = false
                if (entry.failCount or 0) > 0 and entry.lastStatus ~= "ok" and entry.lastStatus ~= "pending" then
                    local backoff = service.GetFailureBackoff(entry.failCount)
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

    function service.MarkAttempt(guid)
        local entry = ensureCacheEntry(guid)
        if not entry then
            return
        end

        entry.lastAttemptAt = API.GetTime()
        entry.lastStatus = "pending"
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
        entry.softExpireAt = now + C.HOT_CACHE_TTL
        entry.hardExpireAt = now + C.WARM_CACHE_TTL
        entry.lastAttemptAt = now
        entry.failCount = 0
        entry.lastStatus = "ok"
        return true
    end

    function service.MarkFailure(guid, status)
        local entry = ensureCacheEntry(guid)
        if not entry then
            return
        end

        entry.lastAttemptAt = API.GetTime()
        entry.failCount = math_min((entry.failCount or 0) + 1, 10)
        entry.lastStatus = status or "failed"
    end

    function service.GetDisplay(guid)
        local entry, state = service.GetState(guid)
        if not entry or not isValidIlvl(entry.ilvl) then
            return nil, nil, nil, nil, false, state
        end

        local stale = state ~= "fresh" or entry.lastStatus ~= "ok"
        local text = string_format("%.1f", entry.ilvl)
        if stale then
            return text .. " (stale)", 1, 0.82, 0, true, state
        end

        return text, 0.2, 1, 0.2, true, state
    end

    return service
end
