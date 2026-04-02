local NS = IlvlTooltip or {}
IlvlTooltip = NS

local API = NS.Api

local pcall = pcall
local string_sub = string.sub
local type = type

local Safe = NS.Safe or {}
NS.Safe = Safe

function Safe.IsGuid(guid)
    return type(guid) == "string"
end

function Safe.GuidEquals(a, b)
    if type(a) ~= "string" or type(b) ~= "string" then
        return false
    end

    local ok, equals = pcall(function()
        return a == b
    end)
    return ok and equals == true
end

function Safe.IsPlayerGuid(guid)
    if type(guid) ~= "string" then
        return false
    end

    local okPrefix, prefix = pcall(string_sub, guid, 1, 7)
    if not okPrefix or type(prefix) ~= "string" then
        return false
    end

    return Safe.GuidEquals(prefix, "Player-")
end

function Safe.UnitExists(unit)
    if type(unit) ~= "string" then
        return false
    end

    local ok, exists = pcall(API.UnitExists, unit)
    return ok and exists == true
end

function Safe.UnitGUID(unit)
    if type(unit) ~= "string" then
        return nil
    end

    local ok, guid = pcall(API.UnitGUID, unit)
    if ok then
        return guid
    end

    return nil
end

function Safe.UnitIsPlayer(unit)
    if type(unit) ~= "string" then
        return false
    end

    local ok, value = pcall(API.UnitIsPlayer, unit)
    return ok and value == true
end

function Safe.CanInspect(unit)
    if type(unit) ~= "string" then
        return false
    end

    local ok, value = pcall(API.CanInspect, unit)
    return ok and value == true
end

function Safe.CheckInteractDistance(unit, index)
    if type(unit) ~= "string" then
        return false
    end

    local ok, value = pcall(API.CheckInteractDistance, unit, index)
    return ok and value == true
end

function Safe.UnitIsUnit(a, b)
    if type(a) ~= "string" or type(b) ~= "string" or not API.UnitIsUnit then
        return false
    end

    local ok, value = pcall(API.UnitIsUnit, a, b)
    return ok and value == true
end

function Safe.UnitTokenFromGUID(guid)
    if type(guid) ~= "string" or not API.UnitTokenFromGUID then
        return nil
    end

    local ok, token = pcall(API.UnitTokenFromGUID, guid)
    if not ok or type(token) ~= "string" then
        return nil
    end

    if not Safe.UnitExists(token) then
        return nil
    end

    local tokenGuid = Safe.UnitGUID(token)
    if not Safe.GuidEquals(tokenGuid, guid) then
        return nil
    end

    return token
end
