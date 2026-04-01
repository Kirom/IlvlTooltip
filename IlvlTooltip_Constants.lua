local NS = IlvlTooltip or {}
IlvlTooltip = NS

NS.Constants = {
    ADDON_PREFIX = "iLvl:",
    HOT_CACHE_TTL = 60,
    WARM_CACHE_TTL = 600,
    INSPECT_COOLDOWN = 1.5,
    INSPECT_TIMEOUT = 2.5,
    RETRY_DELAY = 0.15,
    MAX_RETRIES = 8,
    FAILURE_BACKOFF_BASE = 2,
    FAILURE_BACKOFF_MAX = 15,
    CACHE_SWEEP_INTERVAL = 30,
    GUID_FALLBACK_UNITS = { "mouseover", "target", "focus" },
    INSPECT_SLOTS = {
        1, 2, 3, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16, 17
    },
}

NS.Api = {
    GetTime = GetTime,
    UnitExists = UnitExists,
    UnitGUID = UnitGUID,
    UnitIsPlayer = UnitIsPlayer,
    UnitIsUnit = UnitIsUnit,
    CanInspect = CanInspect,
    CheckInteractDistance = CheckInteractDistance,
    GetAverageItemLevel = GetAverageItemLevel,
    GetDetailedItemLevelInfo = GetDetailedItemLevelInfo,
    GetInventoryItemLink = GetInventoryItemLink,
    UnitTokenFromGUID = UnitTokenFromGUID,
    NotifyInspect = NotifyInspect,
    ClearInspectPlayer = ClearInspectPlayer,
    WorldFrame = WorldFrame,
    GameTooltip = GameTooltip,
    C_Timer = C_Timer,
    C_PaperDollInfo = C_PaperDollInfo,
    TooltipDataProcessor = TooltipDataProcessor,
    Enum = Enum,
    CreateFrame = CreateFrame,
}
