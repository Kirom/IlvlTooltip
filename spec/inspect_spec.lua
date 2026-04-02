local WowMock = require("spec.helpers.wow_mock")
local Loader = require("spec.helpers.addon_loader")

describe("IlvlTooltip inspect orchestrator", function()
    local env
    local NS
    local cache
    local inspect
    local visibleUpdates
    local resolveBestUnitTokenForGuid

    local function isInspectableUnit(unit)
        return _G.UnitExists(unit) and _G.UnitIsPlayer(unit) and _G.CanInspect(unit) and _G.CheckInteractDistance(unit, 1)
    end

    before_each(function()
        env = WowMock.new()
        env:installGlobals()
        NS = Loader.LoadModules({
            "IlvlTooltip_Constants.lua",
            "IlvlTooltip_Safe.lua",
            "IlvlTooltip_Cache.lua",
            "IlvlTooltip_Inspect.lua",
        })

        cache = NS.CreateCache()
        visibleUpdates = {}
        resolveBestUnitTokenForGuid = function(guid, fallbackUnit)
            local safe = NS.Safe
            if fallbackUnit and safe.UnitExists(fallbackUnit) and safe.GuidEquals(safe.UnitGUID(fallbackUnit), guid) then
                return fallbackUnit
            end

            local byGuid = safe.UnitTokenFromGUID(guid)
            if byGuid then
                return byGuid
            end

            return fallbackUnit
        end

        inspect = NS.CreateInspectOrchestrator({
            cache = cache,
            isInspectableUnit = isInspectableUnit,
            resolveBestUnitTokenForGuid = resolveBestUnitTokenForGuid,
            onVisibleUpdate = function(...)
                visibleUpdates[#visibleUpdates + 1] = { ... }
            end,
        })
    end)

    it("deduplicates repeated requests for the same guid", function()
        local guid = "Player-1-00000011"
        env:setUnit("target", {
            guid = guid,
            isPlayer = true,
            canInspect = true,
            inRange = true,
        })

        assert.is_true(inspect.Request("target", guid))
        assert.is_false(inspect.Request("target", guid))
        assert.are.equal(1, #env.inspectRequests)
    end)

    it("rejects non-string guid requests", function()
        env:setUnit("target", {
            guid = "Player-1-00000010",
            isPlayer = true,
            canInspect = true,
            inRange = true,
        })

        assert.is_false(inspect.Request("target", {}))
        assert.is_false(inspect.IsPendingOrQueued({}))
        assert.are.equal(0, #env.inspectRequests)
    end)

    it("writes successful inspect results to cache", function()
        local guid = "Player-1-00000012"
        env:setUnit("target", {
            guid = guid,
            isPlayer = true,
            canInspect = true,
            inRange = true,
        })
        env:setInspectItemLevelFn(function()
            return nil, 640
        end)

        assert.is_true(inspect.Request("target", guid))
        inspect.OnInspectReady(guid)

        local text, _, _, _, hasValue, state = cache.GetDisplay(guid)
        assert.is_true(hasValue)
        assert.are.equal("640.0", text)
        assert.are.equal("fresh", state)
        assert.is_false(inspect.IsWaiting())
        assert.are.equal(1, env.clearInspectCalls)
    end)

    it("treats invalid inspect ilvl payload as failure", function()
        local guid = "Player-1-00000026"
        env:setUnit("target", {
            guid = guid,
            isPlayer = true,
            canInspect = true,
            inRange = true,
        })
        env:setInspectItemLevelFn(function()
            return nil, "640"
        end)

        assert.is_true(inspect.Request("target", guid))
        inspect.OnInspectReady(guid)

        local _, _, _, _, hasValue = cache.GetDisplay(guid)
        assert.is_false(hasValue)
        assert.is_false(inspect.IsWaiting())
        assert.are.equal("Unavailable", visibleUpdates[#visibleUpdates][2])
    end)

    it("does not use zero-arg inspect ilvl fallback", function()
        local guid = "Player-1-00000025"
        env:setUnit("target", {
            guid = guid,
            isPlayer = true,
            canInspect = true,
            inRange = true,
        })
        env:setInspectItemLevelFn(function(unit)
            if unit == nil then
                return nil, 700
            end
            return nil, nil
        end)

        assert.is_true(inspect.Request("target", guid))
        inspect.OnInspectReady(guid)

        local _, _, _, _, hasValue = cache.GetDisplay(guid)
        assert.is_false(hasValue)
        assert.are.equal("Unavailable", visibleUpdates[#visibleUpdates][2])
    end)

    it("resolves loaded inspect data without NotifyInspect via fast path", function()
        local guid = "Player-1-00000016"
        env:setUnit("target", {
            guid = guid,
            isPlayer = true,
            canInspect = true,
            inRange = true,
        })
        env:setInspectItemLevelFn(function()
            return nil, 631
        end)

        local hit = inspect.TryReadLoadedItemLevel("target", guid)
        assert.is_true(hit)
        assert.are.equal(0, #env.inspectRequests)

        local text, _, _, _, hasValue = cache.GetDisplay(guid)
        assert.is_true(hasValue)
        assert.are.equal("631.0", text)
    end)

    it("completes inspect from early probe before INSPECT_READY", function()
        local guid = "Player-1-00000017"
        env:setUnit("target", {
            guid = guid,
            isPlayer = true,
            canInspect = true,
            inRange = true,
        })
        env:setInspectItemLevelFn(function()
            if env.now >= NS.Constants.EARLY_PROBE_DELAY then
                return nil, 642
            end
            return nil, nil
        end)

        assert.is_true(inspect.Request("target", guid))
        assert.are.equal(1, #env.inspectRequests)

        env:advance(NS.Constants.EARLY_PROBE_DELAY + 0.05)

        local text, _, _, _, hasValue = cache.GetDisplay(guid)
        assert.is_true(hasValue)
        assert.are.equal("642.0", text)
        assert.is_false(inspect.IsWaiting())
        assert.are.equal(1, env.clearInspectCalls)
    end)

    it("does not mutate cache via fast path while inspect is pending for the same guid", function()
        local guid = "Player-1-00000018"
        env:setUnit("target", {
            guid = guid,
            isPlayer = true,
            canInspect = true,
            inRange = true,
        })
        env:setInspectItemLevelFn(function()
            return nil, 650
        end)

        assert.is_true(inspect.Request("target", guid))
        local hit = inspect.TryReadLoadedItemLevel("target", guid)
        assert.is_false(hit)
        assert.are.equal(1, #env.inspectRequests)
    end)

    it("cancels queued inspect when fast path resolves that guid", function()
        local guidA = "Player-1-00000027"
        local guidB = "Player-1-00000028"

        env:setUnit("target", {
            guid = guidA,
            isPlayer = true,
            canInspect = true,
            inRange = true,
        })
        env:setUnit("focus", {
            guid = guidB,
            isPlayer = true,
            canInspect = true,
            inRange = true,
        })
        env:setInspectItemLevelFn(function(unit)
            if unit == "focus" then
                return nil, 651
            end
            if unit == "target" then
                return nil, 640
            end
            return nil, nil
        end)

        assert.is_true(inspect.Request("target", guidA))
        assert.is_true(inspect.Request("focus", guidB))
        assert.are.equal(1, #env.inspectRequests)

        local fastHit = inspect.TryReadLoadedItemLevel("focus", guidB)
        assert.is_true(fastHit)

        inspect.OnInspectReady(guidA)
        env:advance(NS.Constants.INSPECT_COOLDOWN + 0.1)
        assert.are.equal(1, #env.inspectRequests)
    end)

    it("recovers from timeout and enters backoff", function()
        local guid = "Player-1-00000013"
        env:setUnit("target", {
            guid = guid,
            isPlayer = true,
            canInspect = true,
            inRange = true,
        })
        env:setInspectItemLevelFn(function()
            return nil, nil
        end)

        assert.is_true(inspect.Request("target", guid))
        env:advance(NS.Constants.INSPECT_TIMEOUT + 0.1)

        assert.is_false(inspect.IsWaiting())
        assert.are.equal("Unavailable", visibleUpdates[#visibleUpdates][2])
        local inBackoff = cache.IsInFailureBackoff(guid)
        assert.is_true(inBackoff)
    end)

    it("processes queued requests after cooldown", function()
        local guidA = "Player-1-00000014"
        local guidB = "Player-1-00000015"

        env:setUnit("target", {
            guid = guidA,
            isPlayer = true,
            canInspect = true,
            inRange = true,
        })
        env:setUnit("focus", {
            guid = guidB,
            isPlayer = true,
            canInspect = true,
            inRange = true,
        })
        env:setInspectItemLevelFn(function()
            return nil, 625
        end)

        assert.is_true(inspect.Request("target", guidA))
        assert.is_true(inspect.Request("focus", guidB))
        assert.are.equal(1, #env.inspectRequests)

        inspect.OnInspectReady(guidA)
        assert.are.equal(1, #env.inspectRequests)

        env:advance(NS.Constants.INSPECT_COOLDOWN + 0.1)
        assert.are.equal(2, #env.inspectRequests)
    end)

    it("prioritizes tooltip requests over queued background requests", function()
        local guidA = "Player-1-00000019"
        local guidB = "Player-1-00000020"
        local guidC = "Player-1-00000021"

        env:setUnit("target", {
            guid = guidA,
            isPlayer = true,
            canInspect = true,
            inRange = true,
        })
        env:setUnit("focus", {
            guid = guidB,
            isPlayer = true,
            canInspect = true,
            inRange = true,
        })
        env:setUnit("mouseover", {
            guid = guidC,
            isPlayer = true,
            canInspect = true,
            inRange = true,
        })
        env:setInspectItemLevelFn(function()
            return nil, 628
        end)

        assert.is_true(inspect.Request("target", guidA))
        assert.is_true(inspect.Request("focus", guidB))
        assert.is_true(inspect.Request("mouseover", guidC, { priority = true }))
        assert.are.equal("target", env.inspectRequests[1])

        inspect.OnInspectReady(guidA)
        env:advance(NS.Constants.INSPECT_COOLDOWN + 0.1)
        assert.are.equal("mouseover", env.inspectRequests[2])
    end)

    it("promotes an already queued guid to priority", function()
        local guidA = "Player-1-00000022"
        local guidB = "Player-1-00000023"
        local guidC = "Player-1-00000024"

        env:setUnit("target", {
            guid = guidA,
            isPlayer = true,
            canInspect = true,
            inRange = true,
        })
        env:setUnit("focus", {
            guid = guidB,
            isPlayer = true,
            canInspect = true,
            inRange = true,
        })
        env:setUnit("mouseover", {
            guid = guidC,
            isPlayer = true,
            canInspect = true,
            inRange = true,
        })
        env:setInspectItemLevelFn(function()
            return nil, 626
        end)

        assert.is_true(inspect.Request("target", guidA))
        assert.is_true(inspect.Request("focus", guidB))
        assert.is_true(inspect.Request("mouseover", guidC))
        assert.is_true(inspect.Request("mouseover", guidC, { priority = true }))

        inspect.OnInspectReady(guidA)
        env:advance(NS.Constants.INSPECT_COOLDOWN + 0.1)
        assert.are.equal("mouseover", env.inspectRequests[2])
    end)
end)
